#' @include stencila.R
NULL

#' The Component class
#'
#' @name Component
#' @export
Component <- function() {
	new('Component')
}
setRefClass(
	'Component',
	contains = 'Extension',
	methods = list(
		show = function(){
			cat(class(.self)[1],'(',address(),')\n',sep='')
		},

		path = function(value){
			get_set_(.self,'Component_path_get','Component_path_set',value)
		},

		address = function(){
			get_(.self,'Component_address_get')
		},

		held = function(){
			get_(.self,'Component_held_get')
		},

		managed = function(value){
			get_set_(.self,'Component_managed_get','Component_managed_set',value)
		},

		origin = function(){
			get_(.self,'Component_origin_get')
		},

		commit = function(message=""){
			method_(.self,'Component_commit',toString(message))
		},

		commits = function(){
			get_(.self,'Component_commits_get')
		},

		version = function(value,message=""){
			if(missing(value)) get_(.self,'Component_version_get')
			else method_(.self,'Component_version',value,message)
		},

		versions = function(){
			get_(.self,'Component_versions_get')
		},

		branch = function(value){
			get_set_(.self,'Component_branch_get','Component_branch_set')
		},

		branches = function(){
			get_(.self,'Component_branches_get')
		},

		sprout = function(new_branch,from_branch){
			method_(.self,'Component_sprout',new_branch,from_branch)
		},

		merge = function(from_branch,to_branch="master"){
			method_(.self,'Component_merge',from_branch,to_branch)
		},

		lop = function(branch){
			method_(.self,'Component_lop',branch)
		},

		serve = function(wait=0){
			url <- method_(.self,paste0(class(.self)[1],'_serve'))
			if(wait){
                cat(url,'\n')
                Sys.sleep(wait)
            }
		},

		view = function(){
			method_(.self,paste0(class(.self)[1],'_view'))
		},

		test = function(task='run'){
			runners <- list(
				runit = list(
					setup = function(){
						dir <- file.path(.self$path,'tests/r/runit')
						if(!file.exists(dir)) dir.create(dir,recursive=TRUE)
						fileName <- file.path(dir,'tests.R')
						if(!file.exists(fileName)){
							fileConn <- file(fileName)
							writeLines(c(
								"require(stencila)",
								"require(RUnit)",
								"",
								"# Write a bunch of `text.*` functions using the `check*` family",
								"# of assertions. Something like this...",
								"#",
								"#   self <- Component('.')",
								"#",
								"#   test.fourty_two <- function(){",
								"#       checkEquals(self$method(),42)",
								"#   }",
								""
							), fileConn)
							close(fileConn)
						}
					},
					run = function(){
						dir <- file.path(.self$path,'tests/r/runit')
						if(file.exists(dir)){
							cat("Running `RUnit` test cases\n")
							require(RUnit)
							# Create a test suite from all test*.R files in the tests/r/runit directory
							suite <- defineTestSuite(
								"tests",
								dirs = dir,
								testFileRegexp = '^test.+\\.R'
							)
							# Run the test suite
							results <- runTestSuite(suite)
							# Print results to user
							print(results)
							# Save results to file
							tsv <- NULL
							for(file in names(results$tests$sourceFileResults)){
								file_data <- results$tests$sourceFileResults[[file]]
								for(func in names(file_data)){
									func_data <- file_data[[func]]
									tsv <- rbind(tsv,data.frame(
										# Remove `dir` from file path
										file = gsub(paste0(dir,"/"),"",file),
										name = func,
										# Recode status
										status = ifelse(func_data$kind=="success","pass",ifelse(func_data$kind=="failure","fail",func_data$kind)),
										# Remove newlines and tabs from message
										message = if(is.null(func_data$msg)) "" else gsub("\t","\\\\t",gsub("\n","\\\\n",func_data$msg))
									))
								}
							}						
							write.table(tsv,file.path(dir,'results.tsv'),row.names=F,col.names=T,quote=F,sep="\t")
						}
					}
				),
				testthat = list(
					setup = function(){
						dir <- file.path(.self$path,'tests/r/testthat')
						if(!file.exists(dir)) dir.create(dir,recursive=TRUE)
						fileName <- file.path(dir,'tests.R')
						if(!file.exists(fileName)){
							fileConn <- file(fileName)
							writeLines(c(
								"require(stencila)",
								"require(testthat)",
								"",
								"# Write a bunch of `test_that` functions using the `expect_*` family",
								"# of assertions. Something like this...",
								"#",
								"#   self <- Component('.')",
								"#",
								"#   test_that('something works',function(){",
								"#       expect_equal(self$method(),42)",
								"#   })",
								""
							), fileConn)
							close(fileConn)
						}
					},
					run = function(){
						dir <- file.path(.self$path,'tests/r/testthat')
						if(file.exists(dir)){
							cat("Running `testthat` test cases\n")
							# Run tests
							require(testthat)
							results <- test_dir(dir)
							# Print results to user
							print(results)
							# Save results to file.
							# Remove columns we don't use
							results$context <- NULL
							results$nb <- NULL
							# Collapse `failed` and `error` columns
							results$status <- 'pass'
							results$status[results$failed!=0] <- 'fail'
							results$status[results$error] <- 'error'
							results$failed <- NULL
							results$error <- NULL
							# Remove tabs and newlines from `test` and put into `name`
							results$name <- gsub("\t","\\\\t",gsub("\n","\\\\n",results$test))
							results$test <- NULL
							write.table(results,file.path(dir,'results.tsv'),row.names=F,col.names=T,quote=F,sep="\t")
						}
					}
				)
			)
			for(runner in runners){
				runner[[task]]()
			}
		}
	)
)

#' Grab a component
#' 
#' This is functionally the same as the Stencila C++ method
#' `Component::get` but will actually instantiate a new member of
#' the retreived class. Not called `get` or `load` because those clash 
#' with functions in the base package
#'
#' @export
grab <- function(address){
	instance <- call_('Component_grab',address)
	return(new(
		instance$type,
		pointer=instance$sexp
	))
}

#' Get a list of held components
#' 
#' See the Stencila C++ method `Component::held_list`.
#' Mostly used for debugging so not exported.
held_list <- function(){
	call_('Component_held_list')
}
