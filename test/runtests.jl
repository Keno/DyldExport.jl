using Cxx
using DyldExport
using Base.Test
# Also test cxxsupport

symbols = Dict{Symbol,Ptr{Void}}(:fooTestDyldExport2=>Ptr{Void}(0x1))
name,handle = DyldExport.export_symbols(symbols)
@show (name,handle)

@show Libdl.dlsym(handle,"fooTestDyldExport2")
@show cglobal(:fooTestDyldExport2)

for i = 1:100
    symbols[symbol("fooDyld$i")] = Ptr{Void}(i)
end
name,handle = DyldExport.export_symbols(symbols)

for i = 1:100
    cglobal(symbol("fooDyld$i"))
end

cxx"""
#include <iostream>
class foo4 {
int x;
public:
foo4(int x);
int bar();
};
foo4::foo4(int x) : x(x) {}
int foo4::bar() { return x; }
"""
@show DyldExport.export_class(pcpp"clang::CXXRecordDecl"(Cxx.lookup_name(Cxx.instance(Cxx.__default_compiler__),["foo4"]).ptr))
@show cglobal(:ZN4foo43barEv)
