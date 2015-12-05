#pragma once

#include <Rcpp.h>

#include <stencila/spread.hpp>

namespace Stencila {

class RSpread : public Spread {
public:

    RSpread(SEXP sexp){
        spread_ = Rcpp::Environment(sexp);
    }

    virtual ~RSpread(void){
    }

    /**
     * Set a cell value
     *
     * @param id ID of the cell
     */
    std::string set(const std::string& id, const std::string& expression, const std::string& alias=""){
        return call_<std::string>(".set",id,expression,alias);
    }

    /**
     * Get a cell value
     *
     * @param id ID of the cell
     */
    std::string get(const std::string& id){
        return call_<std::string>(".get",id);
    }
    
    /**
     * Initialisation of this class
     */
    static void class_init(void){
        Component::class_(RSpreadType,{
            "RSpread",
            nullptr,
            nullptr,
            nullptr
        });
    }

private:

    /**
     * An Rcpp object which represents this spread on the R side
     */
    Rcpp::Environment spread_;

    /**
     * Call a method on the R side spread
     */
    template<typename... Args>
    SEXP call_(const char* name, Args... args){
        Rcpp::Function func = spread_.get(name);
        Rcpp::Language call(func,args...);
        return call.eval();
    }

    /**
     * Call a method on the R side and get the return value
     */
    template<typename Result, typename... Args>
    Result call_(const char* name, Args... args){
        // Currently, this function only handles strings returned from R and then casts those
        // using boost::lexical_cast. I got serious errors of the form:
        //    memory access violation at address: 0x7fff712beff8: no mapping at fault address
        // when trying to use Rcpp::as<bool> or Rcpp::as<int> even when checking the returned SEXP was
        // the correct type
        SEXP result = call_(name,args...);
        if(TYPEOF(result)!=STRSXP) STENCILA_THROW(Exception,"R-side methods should return a string");
        return unstring<Result>(Rcpp::as<std::string>(result));
    }

};

}