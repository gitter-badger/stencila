all: cpp-package py-package r-package

# Get root directory for Stencila project
ROOT := $(realpath .)

# Get the operating system  e.g. linux
OS := $(shell ./config.py os)
# Get the machine architecture e.g i386, x86_64
ARCH := $(shell ./config.py arch)
# Get Stencila version
VERSION :=  $(shell ./config.py version)
# Is this a dirty build (i.e. changes since last commit)?
DIRTY := $(findstring dirty,$(VERSION))

# Build directory uses a heirarchy based on the 
# operating system and machine architecture.
ifndef BUILD
	BUILD := build/$(OS)/$(ARCH)
endif

# Resources directory for downloads of dependencies
# that are independent of build
ifndef RESOURCES
	RESOURCES := build/resources
endif

vars:
	@echo ROOT: $(ROOT)
	@echo OS: $(OS)
	@echo ARCH: $(ARCH)
	@echo VERSION: $(VERSION)
	@echo DIRTY: $(DIRTY)
	@echo BUILD: $(BUILD)
	@echo RESOURCES: $(RESOURCES)
	@echo CXX: $(CXX)

#################################################################################################
# Symbolic links to current build
# 
# Useful for automatically collecting the latest build products

.PHONY: build/current
build/current:
	@mkdir -p $(BUILD)
	@ln -sfT $(OS)/$(ARCH) build/current
build-current: build/current

# During development symlink the `stencila.js` into the 
# Stencila store so it can be served by the embedded server.
# Call this with STORE variable e.g.
#    make build-serve STORE=../../store
build-serve: build/current
	ln -sfT $(ROOT)/build/current $(STORE)/build

#################################################################################################
# C++ requirements

# Collect necessary include an lib directories
CPP_REQUIRES_INC_DIRS := 
CPP_REQUIRES_LIB_DIRS := 

BOOST_VERSION := 1_58_0

$(RESOURCES)/boost_$(BOOST_VERSION).tar.bz2:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ http://prdownloads.sourceforge.net/boost/boost_$(BOOST_VERSION).tar.bz2

$(BUILD)/cpp/requires/boost: $(RESOURCES)/boost_$(BOOST_VERSION).tar.bz2
	mkdir -p $(BUILD)/cpp/requires
	rm -rf $(BUILD)/cpp/requires/boost
	tar --bzip2 -xf $< -C $(BUILD)/cpp/requires
	mv $(BUILD)/cpp/requires/boost_$(BOOST_VERSION) $(BUILD)/cpp/requires/boost
	touch $@

# TODO
#   Need to add the building of libboost_python3.a. This gets built if we add the lines
#		# Python configuration
#		using python : 2.6 ;
#		using python : 2.7 ;
#		using python : 3.2 ;
#   to the project-config.jam.
#   Should use context.env.PYTHON_VERSIONS to do this
#   See http://www.boost.org/doc/libs/1_55_0/libs/python/doc/building.html#id34
#   
#   An alternative may to be to not use a project-config.jam and instead use a hand coded user-config.jam
#   based on one that bootstrap.sh produces.

# Boost is configured with:
#   --with-libraries - so that only those libraries that are needed are built
BOOST_BOOTSTRAP_FLAGS := --with-libraries=atomic,chrono,date_time,filesystem,program_options,python,regex,system,test,thread
ifeq ($(OS), msys)
	# bootstrap.sh must be called with mingw specified as toolset otherwise errors occur
	BOOST_BOOTSTRAP_FLAGS += --with-toolset=mingw
endif

# Boost is built with:
#   --d0 		- supress all informational messages (reduces verbosity which is useful on CI servers)
#   --prefix=.  - so that boost installs into its own directory
#   link=static - so that get statically compiled instead of dynamically compiled libraries
BOOST_B2_FLAGS := -d0 --prefix=. link=static install
ifeq ($(OS), linux)
	# cxxflags=-fPIC - so that the statically compiled library has position independent code for use in shared libraries
	BOOST_B2_FLAGS += cxxflags=-fPIC
endif
ifeq ($(OS), msys)
	# b2 must be called with "system" layout of library names and header locations (otherwise it defaults to 'versioned' on Windows)
	# b2 must be called with "release" build otherwise defaults to debug AND release, which with "system" causes an 
	#   error (http://boost.2283326.n4.nabble.com/atomic-building-with-layout-system-mingw-bug-7482-td4640920.html)
	BOOST_B2_FLAGS += --layout=system release toolset=gcc
endif

$(BUILD)/cpp/requires/boost-built.flag: $(BUILD)/cpp/requires/boost
	cd $< ; ./bootstrap.sh $(BOOST_BOOTSTRAP_FLAGS)
ifeq ($(OS), msys)
	# Under MSYS, project-config.jam must be edited to fix [this error](http://stackoverflow.com/a/5244844/1583041) 
	sed -i "s/mingw/gcc/g" $</project-config.jam
endif
	cd $< ; ./b2 $(BOOST_B2_FLAGS)
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/boost/include
CPP_REQUIRES_LIB_DIRS += -L$(BUILD)/cpp/requires/boost/lib

cpp-requires-boost: $(BUILD)/cpp/requires/boost-built.flag


LIBGIT2_VERSION := 0.22.2

$(RESOURCES)/libgit2-$(LIBGIT2_VERSION).zip:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ https://github.com/libgit2/libgit2/archive/v$(LIBGIT2_VERSION).zip

$(BUILD)/cpp/requires/libgit2: $(RESOURCES)/libgit2-$(LIBGIT2_VERSION).zip
	mkdir -p $(BUILD)/cpp/requires
	rm -rf $@
	unzip -qo $<
	mv libgit2-$(LIBGIT2_VERSION) $@
	touch $@

# For build options see https://libgit2.github.com/docs/guides/build-and-link/
#  	BUILD_CLAR=OFF - do not build tests
#  	BUILD_SHARED_LIBS=OFF - do not build shared library
LIBGIT2_CMAKE_FLAGS := -DBUILD_CLAR=OFF -DBUILD_SHARED_LIBS=OFF
ifeq ($(OS), linux)
	LIBGIT2_CMAKE_FLAGS += -DCMAKE_C_FLAGS=-fPIC
endif
ifeq ($(OS), msys)
	LIBGIT2_CMAKE_FLAGS += -G "MSYS Makefiles"
endif
$(BUILD)/cpp/requires/libgit2-built.flag: $(BUILD)/cpp/requires/libgit2
	cd $< ;\
	  mkdir -p build ;\
	  cd build ;\
	  cmake .. $(LIBGIT2_CMAKE_FLAGS);\
	  cmake --build .
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/libgit2/include
CPP_REQUIRES_LIB_DIRS += -L$(BUILD)/cpp/requires/libgit2/build

cpp-requires-libgit2: $(BUILD)/cpp/requires/libgit2-built.flag


CPP_NETLIB_VERSION := 0.11.1

$(RESOURCES)/cpp-netlib-$(CPP_NETLIB_VERSION)-final.tar.bz2:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ http://storage.googleapis.com/cpp-netlib-downloads/$(CPP_NETLIB_VERSION)/cpp-netlib-$(CPP_NETLIB_VERSION)-final.tar.bz2
	
$(BUILD)/cpp/requires/cpp-netlib: $(RESOURCES)/cpp-netlib-$(CPP_NETLIB_VERSION)-final.tar.bz2
	mkdir -p $(BUILD)/cpp/requires
	rm -rf $@
	tar --bzip2 -xf $< -C $(BUILD)/cpp/requires
	mv $(BUILD)/cpp/requires/cpp-netlib-$(CPP_NETLIB_VERSION)-final $(BUILD)/cpp/requires/cpp-netlib
	touch $@

# cpp-netlib needs to be compiled with OPENSSL_NO_SSL2 defined because SSL2 is insecure and depreciated and on
# some systems (e.g. Ubuntu) OpenSSL is compiled with no support for it
CPP_NETLIB_CMAKE_FLAGS := -DCMAKE_BUILD_TYPE=Debug  -DCMAKE_C_COMPILER=$(CC) -DCMAKE_CXX_COMPILER=$(CXX) -DCMAKE_CXX_FLAGS="-DOPENSSL_NO_SSL2 -O2 -fPIC"
# Under MSYS some additional CMake flags need to be specified
# The "-I/usr/include" in -DCMAKE_CXX_FLAGS seems uncessary but it's not
ifeq ($(OS), msys)
CPP_NETLIB_CMAKE_FLAGS += -G "MSYS Makefiles" -DOPENSSL_INCLUDE_DIR=/usr/include/ -DOPENSSL_LIBRARIES=/usr/lib/ -DCMAKE_CXX_FLAGS="-DOPENSSL_NO_SSL2 -O2 -fPIC -I/usr/include"
endif
$(BUILD)/cpp/requires/cpp-netlib/libs/network/src/libcppnetlib-client-connections.a: $(BUILD)/cpp/requires/cpp-netlib
	cd $(BUILD)/cpp/requires/cpp-netlib; \
		export BOOST_ROOT=../boost ; \
		cmake $(CPP_NETLIB_CMAKE_FLAGS); \
		make cppnetlib-client-connections cppnetlib-server-parsers cppnetlib-uri

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/cpp-netlib/
CPP_REQUIRES_LIB_DIRS += -L$(BUILD)/cpp/requires/cpp-netlib/libs/network/src

cpp-requires-cpp-netlib: $(BUILD)/cpp/requires/cpp-netlib/libs/network/src/libcppnetlib-client-connections.a


PUGIXML_VERSION := 1.6

$(RESOURCES)/pugixml-$(PUGIXML_VERSION).tar.gz:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ http://github.com/zeux/pugixml/releases/download/v$(PUGIXML_VERSION)/pugixml-$(PUGIXML_VERSION).tar.gz

$(BUILD)/cpp/requires/pugixml: $(RESOURCES)/pugixml-$(PUGIXML_VERSION).tar.gz
	mkdir -p $(BUILD)/cpp/requires
	rm -rf $@
	tar xzf $< -C $(BUILD)/cpp/requires
	mv $(BUILD)/cpp/requires/pugixml-$(PUGIXML_VERSION) $(BUILD)/cpp/requires/pugixml

PUGIXML_CXX_FLAGS := -O2
ifeq ($(OS), linux)
	PUGIXML_CXX_FLAGS += -fPIC
endif
$(BUILD)/cpp/requires/pugixml-built.flag: $(BUILD)/cpp/requires/pugixml
	cd $</src ;\
	  $(CXX) -O2 $(PUGIXML_CXX_FLAGS) -c pugixml.cpp ;\
	  $(AR) rcs libpugixml.a pugixml.o
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/pugixml/src
CPP_REQUIRES_LIB_DIRS += -L$(BUILD)/cpp/requires/pugixml/src

cpp-requires-pugixml: $(BUILD)/cpp/requires/pugixml-built.flag


JSONCPP_VERSION := 1.6.2

$(RESOURCES)/jsoncpp-$(JSONCPP_VERSION).tar.gz:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ https://github.com/open-source-parsers/jsoncpp/archive/$(JSONCPP_VERSION).tar.gz

$(BUILD)/cpp/requires/jsoncpp/dist: $(RESOURCES)/jsoncpp-$(JSONCPP_VERSION).tar.gz
	mkdir -p $(BUILD)/cpp/requires
	tar xzf $< -C $(BUILD)/cpp/requires
	cd $(BUILD)/cpp/requires/ ;\
		rm -rf jsoncpp ;\
		mv -f jsoncpp-$(JSONCPP_VERSION) jsoncpp ;\
		cd jsoncpp ;\
			python amalgamate.py ;
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/jsoncpp/dist

cpp-requires-jsoncpp: $(BUILD)/cpp/requires/jsoncpp/dist


TIDYHTML5_VERSION := 8b454f5

$(RESOURCES)/tidy-html5-$(TIDYHTML5_VERSION).tar.gz:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ https://github.com/htacg/tidy-html5/tarball/$(TIDYHTML5_VERSION)

$(BUILD)/cpp/requires/tidy-html5-unpacked.flag: $(RESOURCES)/tidy-html5-$(TIDYHTML5_VERSION).tar.gz
	mkdir -p $(BUILD)/cpp/requires
	rm -rf $@
	tar xzf $< -C $(BUILD)/cpp/requires
	mv $(BUILD)/cpp/requires/htacg-tidy-html5-$(TIDYHTML5_VERSION) $(BUILD)/cpp/requires/tidy-html5
	touch $@

# These patches depend upon `tidy-html5-unpacked.flag` rather than simply the `tidy-html5` since that
# directory's time changes with the patches and so they keep getting applied

# Apply patch to Makefile to add -O2 -fPIC options
$(BUILD)/cpp/requires/tidy-html5/build/gmake/Makefile: cpp/requires/tidy-html5-build-gmake-Makefile.patch $(BUILD)/cpp/requires/tidy-html5-unpacked.flag
	patch $@ $<

# Apply patch from pull request #98 to add <main> tag (this is applied using `patch` rather than `git` so that `git` is not required)
# This patch affects include/tidyenum.h, src/attrdict.h, src/attrdict.c, src/tags.c
$(BUILD)/cpp/requires/tidy-html5/include/tidyenum.h: cpp/requires/tidy-html5-pull-98.patch $(BUILD)/cpp/requires/tidy-html5-unpacked.flag
	cat $< | patch -p1 -d $(BUILD)/cpp/requires/tidy-html5

# Note that we only "make ../../lib/libtidy.a" and not "make all" because the latter is not required
# Under MSYS2 there are lots of multiple definition errors for localize symbols in the library
$(BUILD)/cpp/requires/tidy-html5-built.flag: \
		$(BUILD)/cpp/requires/tidy-html5-unpacked.flag \
		$(BUILD)/cpp/requires/tidy-html5/build/gmake/Makefile \
		$(BUILD)/cpp/requires/tidy-html5/include/tidyenum.h
	cd $(BUILD)/cpp/requires/tidy-html5/build/gmake ;\
	  make ../../lib/libtidy.a
	cd $(BUILD)/cpp/requires/tidy-html5 ;\
	  mkdir -p tidy-html5 ; cp -f include/* tidy-html5 ;\
	  mv lib/libtidy.a lib/libtidy-html5.a
ifeq ($(OS), msys)
	objcopy --localize-symbols=cpp/requires/tidy-html5-localize-symbols.txt $(BUILD)/cpp/requires/tidy-html5/lib/libtidy-html5.a
endif
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/tidy-html5
CPP_REQUIRES_LIB_DIRS += -L$(BUILD)/cpp/requires/tidy-html5/lib

cpp-requires-tidy-html5: $(BUILD)/cpp/requires/tidy-html5-built.flag


WEBSOCKETPP_VERSION := 0.5.1

$(RESOURCES)/websocketpp-$(WEBSOCKETPP_VERSION).zip:
	mkdir -p $(RESOURCES)
	wget --no-check-certificate -O $@ https://github.com/zaphoyd/websocketpp/archive/$(WEBSOCKETPP_VERSION).zip

$(BUILD)/cpp/requires/websocketpp-built.flag: $(RESOURCES)/websocketpp-$(WEBSOCKETPP_VERSION).zip
	rm -rf $(BUILD)/cpp/requires/websocketpp
	unzip -qo $< -d $(BUILD)/cpp/requires
	cd $(BUILD)/cpp/requires ;\
	  mv websocketpp-$(WEBSOCKETPP_VERSION) websocketpp ;\
	  touch websocketpp
	touch $@

CPP_REQUIRES_INC_DIRS += -I$(BUILD)/cpp/requires/websocketpp

cpp-requires-websocketpp: $(BUILD)/cpp/requires/websocketpp-built.flag

# List of libraries to be used below
CPP_REQUIRES_LIBS += boost_filesystem boost_system boost_regex 
CPP_REQUIRES_LIBS += git2 crypto ssl z
CPP_REQUIRES_LIBS += cppnetlib-client-connections cppnetlib-uri boost_thread
CPP_REQUIRES_LIBS += pugixml
CPP_REQUIRES_LIBS += tidy-html5
ifeq ($(OS), linux)
	CPP_REQUIRES_LIBS += rt pthread
endif
ifeq ($(OS), msys)
	CPP_REQUIRES_LIBS += ws2_32 mswsock ssh2
endif

$(BUILD)/cpp/requires: cpp-requires-boost cpp-requires-cpp-netlib cpp-requires-libgit2 cpp-requires-pugixml \
   cpp-requires-jsoncpp cpp-requires-tidy-html5 cpp-requires-websocketpp

cpp-requires: $(BUILD)/cpp/requires

#################################################################################################
# C++ helpers
# These helpers are currently used by the C++ module via system calls. As such they are not required
# to compile Stencila modules but rather provide additional functionality. In the long term the
# system calls to these helpers will be replaced by integrating C++ compatible libraries or replacement code

# PhantomJS is used in `stencil-formats.cpp` for translating ASCIIMath to MathML and for
# creating thumbnails.
# Instead of using PhantomJS, the translation from ASCIIMath to MathML could be done by porting the ASCIIMath.js code to C++
cpp-helpers-phantomjs:
	cd /usr/local/share ;\
		sudo wget https://bitbucket.org/ariya/phantomjs/downloads/phantomjs-1.9.8-linux-x86_64.tar.bz2 ;\
		sudo tar xjf phantomjs-1.9.8-linux-x86_64.tar.bz2 ;\
		sudo ln -s /usr/local/share/phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/share/phantomjs ;\
		sudo ln -s /usr/local/share/phantomjs-1.9.8-linux-x86_64/bin/phantomjs /usr/local/bin/phantomjs ;\

# Sass is used for `make`ing themes (compiling SCSS into minified CSS)
# Instead of using node-sass, libsass could be used in C++ directly
cpp-helpers-sass:
	sudo npm install node-sass -g

# UglifyJS is used for `make`ing themes (compiling JS into minified JS)
cpp-helpers-uglifyjs:
	sudo npm install uglify-js -g

#################################################################################################
# Stencila C++ library

# Build version object file
CPP_VERSION_0 := $(BUILD)/cpp/library/stencila/version.o
$(CPP_VERSION_0):
	@mkdir -p $(BUILD)/cpp/library/stencila
	@echo "#include <stencila/version.hpp>\nconst std::string Stencila::version = \"$(VERSION)\";" > $(BUILD)/cpp/library/stencila/version.cpp
	$(CXX) $(CPP_LIBRARY_FLAGS) -Icpp $(CPP_REQUIRES_INC_DIRS) -o$@ -c $(BUILD)/cpp/library/stencila/version.cpp
# Make it PHONY so it builds every time
.PHONY: $(CPP_VERSION_0)

# Compile Stencila C++ files into object files
CPP_LIBRARY_FLAGS := --std=c++11 -Wall -Wno-unused-local-typedefs -Wno-unused-function -O2
ifeq ($(OS), linux)
	CPP_LIBRARY_FLAGS +=-fPIC
endif
CPP_LIBRARY_CPPS := $(wildcard cpp/stencila/*.cpp)
CPP_LIBRARY_OBJECTS := $(patsubst %.cpp,$(BUILD)/cpp/library/stencila/%.o,$(notdir $(CPP_LIBRARY_CPPS))) $(CPP_VERSION_0)
$(BUILD)/cpp/library/stencila/%.o: cpp/stencila/%.cpp $(BUILD)/cpp/requires
	@mkdir -p $(BUILD)/cpp/library/stencila
	$(CXX) $(CPP_LIBRARY_FLAGS) -Icpp $(CPP_REQUIRES_INC_DIRS) -o$@ -c $<

# Extract object files from requirement libraries
# Care may be required to ensure no name clashes in object files
# Currently this is not dealt with
cpp-library-requires: $(BUILD)/cpp/requires
	@mkdir -p $(BUILD)/cpp/library/requires
	cd $(BUILD)/cpp/library/requires ;\
		ar x ../../requires/boost/lib/libboost_system.a ;\
		ar x ../../requires/boost/lib/libboost_filesystem.a ;\
		ar x ../../requires/boost/lib/libboost_regex.a ;\
		ar x ../../requires/boost/lib/libboost_thread.a ;\
		ar x ../../requires/libgit2/build/libgit2.a ;\
		ar x ../../requires/pugixml/src/libpugixml.a ;\
		ar x ../../requires/tidy-html5/lib/libtidy-html5.a ;\

# Archive all object files (Stencila .cpp files and those extracted from requirements libraries)
# into a single static library.
# Output list of contents to `contents.txt` for checking
$(BUILD)/cpp/library/libstencila.a: $(CPP_LIBRARY_OBJECTS) cpp-library-requires
	cd $(BUILD)/cpp/library ;\
		$(AR) rc libstencila.a `find . -name "*.o"` ;\
		$(AR) t libstencila.a > contents.txt 
cpp-library-staticlib: $(BUILD)/cpp/library/libstencila.a

cpp-library: cpp-library-staticlib

#################################################################################################
# Stencila C++ package
CPP_PACKAGE := stencila-$(OS)-$(ARCH)-$(VERSION).tar.gz
CPP_PACKAGE_BUILD := $(BUILD)/cpp/package/$(CPP_PACKAGE)

# Copy over Stencila header files
CPP_STENCILA_HPPS := $(wildcard cpp/stencila/*.hpp)
CPP_PACKAGE_HPPS := $(patsubst %.hpp,$(BUILD)/cpp/package/stencila/stencila/%.hpp,$(notdir $(CPP_STENCILA_HPPS)))
$(BUILD)/cpp/package/stencila/stencila/%.hpp: cpp/stencila/%.hpp
	@mkdir -p $(BUILD)/cpp/package/stencila/stencila
	cp $< $@

# Zip it up
$(CPP_PACKAGE_BUILD): $(CPP_PACKAGE_HPPS) $(BUILD)/cpp/library/libstencila.a
	cp $(BUILD)/cpp/library/libstencila.a $(BUILD)/cpp/package/stencila
	cd $(BUILD)/cpp/package ; tar czf stencila-$(OS)-$(ARCH)-$(VERSION).tar.gz stencila
cpp-package: $(CPP_PACKAGE_BUILD)

# Deliver C++ package to get.stenci.la
cpp-deliver: $(CPP_PACKAGE_BUILD)
ifeq (dirty,$(DIRTY))
	$(error Delivery is not done for dirty versions: $(VERSION). Commit first.)
else
	aws s3 cp $(CPP_PACKAGE_BUILD) s3://get.stenci.la/cpp/$(CPP_PACKAGE) --cache-control max-age=31536000
endif


#################################################################################################
# Stencila C++ tests

# Compile options for tests include:
# 		-g (debug symbols)
# 		-O0 (no optimizations, so coverage is valid)
# 		--coverage (for coverage instrumentation)
CPP_TEST_COMPILE := $(CXX) --std=c++11 -Wall -Wno-unused-local-typedefs -Wno-unused-function \
                       -g -O0 --coverage -fPIC -Icpp $(CPP_REQUIRES_INC_DIRS)

CPP_TEST_LIB_DIRS := $(CPP_REQUIRES_LIB_DIRS)

CPP_TEST_LIBS := $(CPP_REQUIRES_LIBS) boost_unit_test_framework gcov
CPP_TEST_LIBS := $(patsubst %, -l%,$(CPP_TEST_LIBS))

# Compile a test file into an object file
# $(realpath $<) is used for consistency of paths in coverage reports
CPP_TEST_OS := $(patsubst %.cpp,$(BUILD)/cpp/tests/%.o,$(notdir $(wildcard cpp/tests/*.cpp)))
$(BUILD)/cpp/tests/%.o: cpp/tests/%.cpp
	@mkdir -p $(BUILD)/cpp/tests
	$(CPP_TEST_COMPILE) -o$@ -c $(realpath $<)

# Compile a stencila source file into an object file
# This needs to be done (instead of linking to libstencila.a) so that coverage statistics
# can be generated for these files
# $(realpath $<) is used for consistency of paths in coverage reports
CPP_TEST_STENCILA_OS := $(patsubst %.cpp,$(BUILD)/cpp/tests/stencila/%.o,$(notdir $(wildcard cpp/stencila/*.cpp))) $(CPP_VERSION_0)
$(BUILD)/cpp/tests/stencila/%.o: cpp/stencila/%.cpp
	@mkdir -p $(BUILD)/cpp/tests/stencila
	$(CPP_TEST_COMPILE) -o$@ -c $(realpath $<)

# Compile a single test file into an executable
$(BUILD)/cpp/tests/%.exe: $(BUILD)/cpp/tests/%.o $(BUILD)/cpp/tests/tests.o $(CPP_TEST_STENCILA_OS) $(BUILD)/cpp/requires
	$(CPP_TEST_COMPILE) -o$@ $< $(BUILD)/cpp/tests/tests.o $(CPP_TEST_STENCILA_OS) $(CPP_TEST_LIB_DIRS) $(CPP_TEST_LIBS)

# Compile all test files into an executable
$(BUILD)/cpp/tests/tests.exe: $(CPP_TEST_OS) $(CPP_TEST_STENCILA_OS) $(BUILD)/cpp/requires
	$(CPP_TEST_COMPILE) -o$@ $(CPP_TEST_OS) $(CPP_TEST_STENCILA_OS) $(CPP_TEST_LIB_DIRS) $(CPP_TEST_LIBS)

# Make test executable precious so they are kept despite
# being intermediaries for test runs
.PRECIOUS: $(BUILD)/cpp/tests/%.exe

# Run a test
# Limit memory to prevent bugs like infinite recursion from filling up the
# machine's memory. This needs to be quite high for some tests. 2Gb = 2,097,152 kb
$(BUILD)/cpp/tests/%: $(BUILD)/cpp/tests/%.exe
	ulimit -v 2097152; ($<) || (exit 1)

# Run a single test suite by specifying in command line e.g.
# 	make cpp-test CPP_TEST=stencil-cila
# Creates a symlink so the debugger picks this test as the one
# to debug
ifndef CPP_TEST
  CPP_TEST := tests
endif
cpp-test: build-current $(BUILD)/cpp/tests/$(CPP_TEST).exe
	cd $(BUILD)/cpp/tests/ ;\
		ln -sfT $(CPP_TEST).exe test-to-debug ;\
		ulimit -v 2097152 ;\
		(./$(CPP_TEST).exe) || (exit 1)

# Run quick tests only
cpp-tests-quick: $(BUILD)/cpp/tests/tests.exe
	ulimit -v 2097152; ($< --run_test=*_quick/*) || (exit 1)

# Run all tests
cpp-tests: $(BUILD)/cpp/tests/tests

# Run all tests and report results and coverage to XML files
# Requires python, xsltproc and [gcovr](http://gcovr.com/guide.html):
#   sudo apt-get install xsltproc
#   sudo pip install gcovr
# Use of 
#   gcovr --root $(ROOT) --filter='.*/cpp/stencila/.*'
# below seems to be necessary when there are different source and build directories to
# only produce coverage reports for files in 'cpp/stencila' 

# Run all tests and generate coverage stats
cpp-tests-coverage: $(BUILD)/cpp/tests/tests.exe
	cd $(BUILD)/cpp/tests ;\
	  # Run all tests \
	  ./tests.exe;\
	  # Produce coverage stats using gcovr helper for gcov \
	  gcovr --root $(ROOT) --filter='.*/cpp/stencila/.*'

# Run all tests and report results to Junit compatible XML files and coverage X
# to Cobertura comparible XML files
$(BUILD)/cpp/tests/boost-test-to-junit.xsl: cpp/tests/boost-test-to-junit.xsl
	cp $< $@
cpp-tests-xml: $(BUILD)/cpp/tests/tests.exe $(BUILD)/cpp/tests/boost-test-to-junit.xsl
	cd $(BUILD)/cpp/tests ;\
	  # Run all tests with reporting to XML file \
	  ./tests.exe --report_format=xml --report_level=detailed --log_format=xml --log_level=test_suite > boost-test-out.xml 2>&1 ;\
	  # Because redirecting stdout and stderr to one file need to wrap in an outer tag \
	  python -c "print '<xml>',file('boost-test-out.xml').read(),'</xml>'" > boost-test.xml ;\
	  # Convert to Junit XML format \
	  xsltproc --output junit.xml boost-test-to-junit.xsl boost-test.xml ;\
	  # Produce coverage report \
	  gcovr --root $(ROOT) --filter='.*/cpp/stencila/.*' --xml --output=coverage.xml

# Run all tests and create coverage to HTML files
# Useful for examining coverage during local development 
cpp-tests-html: $(BUILD)/cpp/tests/tests.exe
	cd $(BUILD)/cpp/tests ;\
	  # Run all tests \
	  ./tests.exe;\
	  # Produce coverage report \
	  gcovr --root $(ROOT) --filter='.*/cpp/stencila/.*' --html --html-details --output=coverage.html

cpp-tests-clean:
	rm -rf $(BUILD)/cpp/tests


#################################################################################################
# C++ documentation

$(BUILD)/cpp/docs/Doxyfile: cpp/docs/Doxyfile
	@mkdir -p $(BUILD)/cpp/docs
	cp $< $@

$(BUILD)/cpp/docs/%.css: cpp/docs/%.css
	@mkdir -p $(BUILD)/cpp/docs
	cp $< $@

$(BUILD)/cpp/docs/%.html: cpp/docs/%.html
	@mkdir -p $(BUILD)/cpp/docs
	cp $< $@
	
cpp-docs: $(BUILD)/cpp/docs/Doxyfile $(BUILD)/cpp/docs/doxy.css \
	      $(BUILD)/cpp/docs/doxy-header.html $(BUILD)/cpp/docs/doxy-footer.html
	cd $(BUILD)/cpp/docs ;\
	  sed -i 's!PROJECT_NUMBER = .*$$!PROJECT_NUMBER = $(VERSION)!' Doxyfile ;\
	  sed -i 's!INPUT = .*$$!INPUT = $(ROOT)/cpp/stencila/!' Doxyfile ;\
	  doxygen Doxyfile

# Remove everything except C++ requirements
cpp-scrub:
	rm -rf $(BUILD)/cpp/library $(BUILD)/cpp/tests $(BUILD)/cpp/docs

# Remove everything
cpp-clean:
	rm -rf $(BUILD)/cpp

#################################################################################################
# Stencila console program

$(BUILD)/console/stencila: console/stencila.cpp $(BUILD)/cpp/requires
	@mkdir -p $(BUILD)/console
	$(CXX) --std=c++11 -Wall -Wno-unused-local-typedefs -Wno-unused-function -O2 \
	   -Icpp -Ipy -Ir $(CPP_REQUIRES_INC_DIRS) \
	   -L$(BUILD)/cpp/library -Lcpp/requires/lib \
	   -o$@ $< \
	   -lstencila $(patsubst %, -l%,$(CPP_REQUIRES_LIBS)) \
	   -lpython2.7 -lboost_python \
	   

console-build: $(BUILD)/console/stencila

#################################################################################################
# Stencila Javascript package

REQUIREJS_VERSION := 2.1.17

$(RESOURCES)/require-$(REQUIREJS_VERSION).js:
	@mkdir -p $(RESOURCES)
	wget -O$@ http://requirejs.org/docs/release/$(REQUIREJS_VERSION)/comments/require.js

REQUIREJS_TEXT_VERSION := 2.0.14

$(RESOURCES)/require-text-$(REQUIREJS_TEXT_VERSION).tar.gz:
	@mkdir -p $(RESOURCES)
	wget --no-check-certificate -O$@ https://github.com/requirejs/text/archive/$(REQUIREJS_TEXT_VERSION).tar.gz

# Make the text.js plugin "inlineable"
$(BUILD)/js/requires/text-$(REQUIREJS_TEXT_VERSION)/text.js: $(RESOURCES)/require-text-$(REQUIREJS_TEXT_VERSION).tar.gz
	@mkdir -p $(BUILD)/js/requires
	tar xzf $< -C $(BUILD)/js/requires
	sed -i "s/define(\['module'\]/define('text',\['module'\]/g" $@
	
JQUERY_VERSION := 2.1.4

$(RESOURCES)/jquery-$(JQUERY_VERSION).js:
	@mkdir -p $(RESOURCES)
	wget -O$@ http://code.jquery.com/jquery-$(JQUERY_VERSION).js

JQUERY_COOKIE_VERSION := 1.4.1

$(RESOURCES)/jquery.cookie-$(JQUERY_COOKIE_VERSION).min.js:
	@mkdir -p $(RESOURCES)
	wget --no-check-certificate -O$@ https://github.com/carhartl/jquery-cookie/releases/download/v$(JQUERY_COOKIE_VERSION)/jquery.cookie-$(JQUERY_COOKIE_VERSION).min.js

JQUERY_HOTKEYS_VERSION := 0.2.0

$(RESOURCES)/jquery.hotkeys-$(JQUERY_HOTKEYS_VERSION).tar.gz:
	@mkdir -p $(RESOURCES)
	wget --no-check-certificate -O$@ https://github.com/jeresig/jquery.hotkeys/archive/$(JQUERY_HOTKEYS_VERSION).tar.gz

$(BUILD)/js/requires/jquery.hotkeys-$(JQUERY_HOTKEYS_VERSION)/jquery.hotkeys.js: $(RESOURCES)/jquery.hotkeys-$(JQUERY_HOTKEYS_VERSION).tar.gz
	@mkdir -p $(BUILD)/js/requires
	tar xzf $< -C $(BUILD)/js/requires
	touch $@

# Build a minified file of all JS requirements for `stencila.js`
$(BUILD)/js/requires.min.js: \
			$(RESOURCES)/require-$(REQUIREJS_VERSION).js \
			$(BUILD)/js/requires/text-$(REQUIREJS_TEXT_VERSION)/text.js \
	        $(RESOURCES)/jquery-$(JQUERY_VERSION).js \
	        $(BUILD)/js/requires/jquery.hotkeys-$(JQUERY_HOTKEYS_VERSION)/jquery.hotkeys.js
	@mkdir -p $(BUILD)/js
	uglifyjs $^ --compress --mangle --comments 	> $@

JASMINE_VERSION := 2.3.4

$(RESOURCES)/jasmine-standalone-$(JASMINE_VERSION).zip:
	@mkdir -p $(RESOURCES)
	wget --no-check-certificate -O$@ https://github.com/jasmine/jasmine/releases/download/v$(JASMINE_VERSION)/jasmine-standalone-$(JASMINE_VERSION).zip
	
$(BUILD)/js/requires/jasmine-$(JASMINE_VERSION): $(RESOURCES)/jasmine-standalone-$(JASMINE_VERSION).zip
	@mkdir -p $(BUILD)/js/requires
	unzip -qoj $< 'lib/jasmine-$(JASMINE_VERSION)/*' -d $(BUILD)/js/requires/jasmine-$(JASMINE_VERSION)

$(BUILD)/js/requires/jasmine-$(JASMINE_VERSION)/mock-ajax.js: $(BUILD)/js/requires/jasmine-$(JASMINE_VERSION)
	wget --no-check-certificate -O$@ https://raw.github.com/jasmine/jasmine-ajax/master/lib/mock-ajax.js

# Run Javascript tests
js-tests: build/current $(BUILD)/js/requires.min.js $(BUILD)/js/requires/jasmine-$(JASMINE_VERSION) $(BUILD)/js/requires/jasmine-$(JASMINE_VERSION)/mock-ajax.js
	(phantomjs js/tests/spec-runner.js js/tests/spec-runner.html)  || (exit 1)

# Provide files needed to serve files from the Javascript modules during development
# You must run the make taks `build-serve` see above.
js-develop: $(BUILD)/js/requires.min.js
	ln -sfT $(ROOT)/js/stencila.js $(BUILD)/js/stencila.js

JS_MIN := $(BUILD)/js/stencila-$(VERSION).min.js
$(JS_MIN) : $(BUILD)/js/requires.min.js js/stencila.js
	uglifyjs $^ --compress --mangle > $@
js-build: $(JS_MIN)

# Deliver Javascript to get.stenci.la
js-deliver: $(JS_MIN)
ifeq (dirty,$(DIRTY))
	$(error Delivery is not done for dirty versions: $(VERSION). Commit first.)
else
	aws s3 cp $(JS_MIN) s3://get.stenci.la/js/ --content-type application/json --cache-control max-age=31536000
endif

js-clean:
	rm -f $(BUILD)/js/requires.min.js


#################################################################################################
# Stencila Python package

# If PY_VERSION is not defined then get it
ifndef PY_VERSION
  PY_VERSION := $(shell ./config.py py_version)
endif

PY_BUILD := $(BUILD)/py/$(PY_VERSION)

ifeq ($(OS), linux)
  PY_INCLUDE_DIR := /usr/include/python$(PY_VERSION)
  PY_EXE := python$(PY_VERSION)
endif

PY_BOOST_PYTHON_LIB := boost_python
#ifeq $(or $(if $(OS),3.0), $(if $(OS),3.0)
#	PY_BOOST_PYTHON_LIB += 3
#endif

PY_PACKAGE_PYS := $(patsubst %.py,$(PY_BUILD)/stencila/%.py,$(notdir $(wildcard py/stencila/*.py)))
PY_PACKAGE_OBJECTS := $(patsubst %.cpp,$(PY_BUILD)/objects/%.o,$(notdir $(wildcard py/stencila/*.cpp)))

PY_CXX_FLAGS := --std=c++11 -Wall -Wno-unused-local-typedefs -Wno-unused-function -O2 -fPIC

PY_SETUP_EXTRA_OBJECTS := $(patsubst $(PY_BUILD)/%,%,$(PY_PACKAGE_OBJECTS))
PY_SETUP_LIB_DIRS := ../../cpp/library ../../cpp/requires/boost/lib
PY_SETUP_LIBS := stencila $(PY_BOOST_PYTHON_LIB) python$(PY_VERSION) rt crypto ssl z

# Print Python related Makefile variables; useful for debugging
py-vars:
	@echo PY_VERSION : $(PY_VERSION)
	@echo PY_BUILD : $(PY_BUILD)

$(PY_BUILD)/stencila/%.py: py/stencila/%.py
	@mkdir -p $(PY_BUILD)/stencila
	cp $< $@

$(PY_BUILD)/objects/%.o: py/stencila/%.cpp $(BUILD)/cpp/requires
	@mkdir -p $(PY_BUILD)/objects
	$(CXX) $(PY_CXX_FLAGS) -Icpp $(CPP_REQUIRES_INC_DIRS) -I$(PY_INCLUDE_DIR) -o$@ -c $<

# Copy setup.py to build directory and run it from there
# Create and touch a `dummy.cpp` for setup.py to build
# Record name of the wheel to file for reading by other build tasks
$(PY_BUILD)/latest.txt: py/setup.py py/scripts/stencila-py $(PY_PACKAGE_PYS) $(PY_PACKAGE_OBJECTS) $(BUILD)/cpp/library/libstencila.a
	cp py/setup.py $(PY_BUILD)
	mkdir -p $(PY_BUILD)/scripts
	cp py/scripts/stencila-py $(PY_BUILD)/scripts/stencila-py
	cd $(PY_BUILD)/ ;\
		export \
			VERSION=$(VERSION) \
			EXTRA_OBJECTS='$(PY_SETUP_EXTRA_OBJECTS)' \
			LIBRARY_DIRS='$(PY_SETUP_LIB_DIRS)' \
			LIBRARIES='$(PY_SETUP_LIBS)' ;\
		touch dummy.cpp ;\
		$(PY_EXE) setup.py bdist_wheel
	cd $(PY_BUILD)/dist; echo `ls -rt *.whl | tail -n1` > ../latest.txt

py-package: $(PY_BUILD)/latest.txt

# Create a virtual environment to be used for testing with the Python version
# Using a virtual environment allows the Stencila wheel to be installed locally,
# i.e. without root privalages, and also does not affect the host machines Python setup 
$(PY_BUILD)/testenv/bin/activate:
	@mkdir -p $(PY_BUILD);
	cd $(PY_BUILD) ;\
		virtualenv --python=python$(PY_VERSION) --no-site-packages testenv

$(PY_BUILD)/testenv/lib/python$(PY_VERSION)/site-packages/stencila: $(PY_BUILD)/testenv/bin/activate $(PY_BUILD)/latest.txt
	@mkdir -p $(PY_BUILD);
	cd $(PY_BUILD) ;\
		. testenv/bin/activate ;\
		pip install --upgrade --force-reinstall dist/`cat latest.txt`

py-tests: py/tests/tests.py $(PY_BUILD)/testenv/lib/python$(PY_VERSION)/site-packages/stencila
	cp py/tests/tests.py $(PY_BUILD)/testenv
	cd $(PY_BUILD)/testenv ;\
		. bin/activate ;\
		(python tests.py)||(exit 1)

py-install: $(PY_BUILD)/testenv/bin/activate $(PY_BUILD)/latest.txt
	cd $(PY_BUILD) ;\
		sudo pip install --upgrade --force-reinstall dist/`cat latest.txt`

py-clean:
	rm -rf $(PY_BUILD)

# Deliver Python package to get.stenci.la
py-deliver: py-package
ifeq (dirty,$(DIRTY))
	$(error Delivery is not done for dirty versions: $(VERSION). Commit first.)
else
	$(eval PY_WHEEL := $(shell cat $(PY_BUILD)/latest.txt))
	aws s3 cp $(PY_BUILD)/dist/$(PY_WHEEL) s3://get.stenci.la/py/
endif

#################################################################################################
# R requirements

RCPP_VERSION = 0.11.5

$(RESOURCES)/Rcpp_$(RCPP_VERSION).tar.gz:
	@mkdir -p $(RESOURCES)
	wget --no-check-certificate -O$@ http://cran.r-project.org/src/contrib/Archive/Rcpp/Rcpp_$(RCPP_VERSION).tar.gz
	
$(BUILD)/r/requires/Rcpp: $(RESOURCES)/Rcpp_$(RCPP_VERSION).tar.gz
	@mkdir -p $@
	R CMD INSTALL -l $(BUILD)/r/requires $<
r-requires-rcpp: $(BUILD)/r/requires/Rcpp

$(BUILD)/r/requires: $(BUILD)/r/requires/Rcpp
r-requires: $(BUILD)/r/requires

#################################################################################################
# Stencila R package

# If R_VERSION is not defined then get it
ifndef R_VERSION
  # Version number excludes any patch number
  R_VERSION := $(shell Rscript -e "cat(R.version\$$major,strsplit(R.version\$$minor,'\\\\.')[[1]][1],sep='.')" )
endif

R_BUILD := $(BUILD)/r/$(R_VERSION)

# Define R platform
# Note in the below the double $ is to escape make's treatment of $
# and the \$ is to escape the shell's treatment of $
R_PLATFORM := $(shell Rscript -e "cat(R.version\$$platform)" )

# The R version can not include any of the non numeric suffixes (commit and/or dirty)
R_PACKAGE_VERSION := $(firstword $(subst -, ,$(VERSION)))

# Define other platform specific variables...
ifeq ($(OS),linux)
R_PACKAGE_EXT := tar.gz
R_DYNLIB_EXT := so
R_REPO_PACKAGE_DIR := $(R_BUILD)/repo/src/contrib
R_REPO_TYPE := source
endif
ifeq ($(OS),msys)
R_PACKAGE_EXT := zip
R_DYNLIB_EXT := dll
R_REPO_PACKAGE_DIR := $(R_BUILD)/repo/bin/windows/contrib/$(STENCILA_R_VERSION)
R_REPO_TYPE := win.binary
endif
# Define where the shared library gets put
R_DYNLIB_NAME := stencila_$(R_PACKAGE_VERSION)
R_DYNLIB_FILE := $(R_DYNLIB_NAME).$(R_DYNLIB_EXT)
R_REPO_DYNLIB_DIR := $(R_BUILD)/repo/lib/$(R_PLATFORM)/$(R_VERSION)

# Print R related Makefile variables; useful for debugging
r-vars:
	@echo R_VERSION : $(R_VERSION)
	@echo R_PLATFORM : $(R_PLATFORM)
	@echo R_PACKAGE_VERSION : $(R_PACKAGE_VERSION)
	@echo R_DYNLIB_FILE : $(R_DYNLIB_FILE)
	@echo R_REPO_PACKAGE_DIR : $(R_REPO_PACKAGE_DIR)
	@echo R_REPO_TYPE : $(R_REPO_TYPE)
	@echo R_REPO_DYNLIB_DIR : $(R_REPO_DYNLIB_DIR)

# Compile each cpp file
R_PACKAGE_OBJECTS := $(patsubst %.cpp,$(R_BUILD)/objects/%.o,$(notdir $(wildcard r/stencila/*.cpp)))
R_CXX_FLAGS := --std=c++11 -Wall -Wno-unused-local-typedefs -Wno-unused-function -O2 -fPIC
R_INCLUDE_DIR := /usr/share/R/include
R_INCLUDES := -Icpp $(CPP_REQUIRES_INC_DIRS) \
              -I$(R_INCLUDE_DIR) \
              -I$(BUILD)/r/requires/Rcpp/include
$(R_BUILD)/objects/%.o: r/stencila/%.cpp $(BUILD)/cpp/requires $(BUILD)/r/requires
	@mkdir -p $(R_BUILD)/objects
	$(CXX) $(R_CXX_FLAGS) $(R_INCLUDES) -o$@ -c $<
	
# Create shared library
R_DYNLIB_LIB_DIRS := -L$(BUILD)/cpp/library $(CPP_REQUIRES_LIB_DIRS)
R_DYNLIB_LIBS := stencila $(CPP_REQUIRES_LIBS) 
$(R_BUILD)/$(R_DYNLIB_FILE): $(R_PACKAGE_OBJECTS) $(BUILD)/cpp/library/libstencila.a
	$(CXX) -shared -o$@ $^ $(R_DYNLIB_LIB_DIRS) $(patsubst %, -l%,$(R_DYNLIB_LIBS))

# Place zipped up shared library in package
# There should only ever be one platform/version dynamic library in a package , so wipe the `inst/lib` dir first
R_PACKAGE_LIBZIP := $(R_BUILD)/stencila/inst/lib/$(R_PLATFORM)/$(R_VERSION)/$(R_DYNLIB_FILE).zip
$(R_PACKAGE_LIBZIP): $(R_BUILD)/$(R_DYNLIB_FILE)
	rm -rf $(R_BUILD)/stencila/inst/lib/
	@mkdir -p $(R_BUILD)/stencila/inst/lib/$(R_PLATFORM)/$(R_VERSION)
	zip -j $@ $<

# Copy over `stencila-r`
R_PACKAGE_CLI := $(R_BUILD)/stencila/inst/bin/stencila-r
$(R_PACKAGE_CLI): r/stencila-r
	@mkdir -p $(R_BUILD)/stencila/inst/bin
	cp $< $@

# Copy over `install.libs.R`
R_PACKAGE_INSTALLSCRIPT := $(R_BUILD)/stencila/src/install.libs.R
$(R_PACKAGE_INSTALLSCRIPT): r/install.libs.R
	@mkdir -p $(R_BUILD)/stencila/src/
	cp $< $@

# Create a dummy C source code file in `src`
# If there is no source files in `src` then `src\install.libs.R` is not run. 
R_PACKAGE_DUMMYC := $(R_BUILD)/stencila/src/dummy.c
$(R_PACKAGE_DUMMYC):
	@mkdir -p $(R_BUILD)/stencila/src/
	touch $@

# Copy over each R file
R_PACKAGE_RS := $(patsubst %, $(R_BUILD)/stencila/R/%, $(notdir $(wildcard r/stencila/*.R)))
$(R_BUILD)/stencila/R/%.R: r/stencila/%.R
	@mkdir -p $(R_BUILD)/stencila/R
	cp $< $@

# Copy over each unit test file
R_PACKAGE_TESTS := $(patsubst %, $(R_BUILD)/stencila/inst/unitTests/%, $(notdir $(wildcard r/tests/*.R)))
$(R_BUILD)/stencila/inst/unitTests/%.R: r/tests/%.R
	@mkdir -p $(R_BUILD)/stencila/inst/unitTests
	cp $< $@

# Copy over DESCRIPTION
R_PACKAGE_DESC := $(R_BUILD)/stencila/DESCRIPTION
$(R_PACKAGE_DESC): r/DESCRIPTION
	cp $< $@

# Finalise the package directory
R_PACKAGE_DATE := $(shell date --utc +%Y-%m-%dT%H:%M:%SZ)
$(R_BUILD)/stencila: $(R_PACKAGE_LIBZIP) $(R_PACKAGE_CLI) $(R_PACKAGE_INSTALLSCRIPT) $(R_PACKAGE_DUMMYC) $(R_PACKAGE_RS) $(R_PACKAGE_TESTS) $(R_PACKAGE_DESC)
	# Edit package version and date using sed:
	#	.* = anything, any number of times
	#	$ = end of line
	# The $ needs to be doubled for escaping make
	# ISO 8601 date/time stamp used: http://en.wikipedia.org/wiki/ISO_8601
	sed -i 's!Version: .*$$!Version: $(R_PACKAGE_VERSION)!' $(R_PACKAGE_DESC)
	sed -i 's!Date: .*$$!Date: $(R_PACKAGE_DATE)!' $(R_PACKAGE_DESC)
	# Run roxygen to generate Rd files and NAMESPACE file
	cd $(R_BUILD) ;\
		rm -f stencila/man/*.Rd ;\
		Rscript -e "library(roxygen2);roxygenize('stencila');"
	# Add `useDynLib` to the NAMESPACE file (after roxygensiation) so that
	# the dynamic library is loaded
	echo "useDynLib($(R_DYNLIB_NAME))" >> $(R_BUILD)/stencila/NAMESPACE
	# Touch the directory to ensure it is newer than its contents
	touch $@
r-package-dir: $(R_BUILD)/stencila

# Check the package by running R CMD check
# on the package directory. Do this in the
# build directory to prevent polluting source tree
r-package-check: $(R_BUILD)/stencila
	cd $(R_BUILD) ;\
	  R CMD check stencila

# Build the package
R_PACKAGE_FILE := stencila_$(R_PACKAGE_VERSION).$(R_PACKAGE_EXT)
$(R_BUILD)/$(R_PACKAGE_FILE): $(R_BUILD)/stencila
ifeq ($(OS),linux)
	cd $(R_BUILD); R CMD build stencila
endif
ifeq ($(OS),msys)
	cd $(R_BUILD); R CMD INSTALL --build stencila
endif
r-package: $(R_BUILD)/$(R_PACKAGE_FILE)

# Deposit package into local repository
# See http://cran.r-project.org/doc/manuals/R-admin.html#Setting-up-a-package-repository
r-repo: r-package
	# Make R package repository sub directory
	mkdir -p $(R_REPO_PACKAGE_DIR)
	# Copy package there
	cp $(R_BUILD)/$(R_PACKAGE_FILE) $(R_REPO_PACKAGE_DIR)
	# Generate the PACKAGE file for the repo
	Rscript -e "tools::write_PACKAGES('$(R_REPO_PACKAGE_DIR)',type='$(R_REPO_TYPE)')"
	# Make the directory for the shared dynamic library
	mkdir -p $(R_REPO_DYNLIB_DIR)
	# Copy the library zip file there
	cp $(R_PACKAGE_LIBZIP) $(R_REPO_DYNLIB_DIR)

# Deliver R package to get.stenci.la
r-deliver: r-package
ifeq (dirty,$(DIRTY))
	$(error Delivery is not done for dirty versions: $(VERSION). Commit first.)
else
	aws s3 cp $(R_BUILD)/$(R_PACKAGE_FILE) s3://get.stenci.la/r/complete/$(R_PLATFORM)/$(R_VERSION)/
endif

# Test the package by running unit tests
# Install package in a testenv directory and run unit tests from there
# This is better than installing package in the user's R library location
r-tests: $(R_BUILD)/$(R_PACKAGE_FILE)
	cd $(R_BUILD) ;\
	  mkdir -p testenv ;\
	  R CMD INSTALL -l testenv $(R_PACKAGE_FILE) ;\
	  cd testenv ;\
	    (Rscript -e "library(stencila,lib.loc='.'); setwd('stencila/unitTests/'); source('do-svUnit.R'); quit(save='no',status=fails);") || (exit 1)

# Install R on the local host
# Not intended for development but rather 
# to install on the host machine after a build
r-install: $(R_BUILD)/$(R_PACKAGE_FILE)
	sudo R CMD INSTALL $(R_BUILD)/$(R_PACKAGE_FILE)
	sudo Rscript -e 'library(stencila);stencila:::install()'

# Remove everything except R requirements
r-scrub:
	rm -rf $(R_BUILD)/objects $(R_BUILD)/stencila $(R_BUILD)/$(R_DYNLIB) $(R_BUILD)/$(R_PACKAGE_FILE) $(R_BUILD)/testenv

# Remove everything
r-clean:
	rm -rf $(BUILD)/r

#################################################################################################

# Clean everything!
clean:
	rm -rf $(BUILD)