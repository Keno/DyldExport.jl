using DyldExport
using Base.Test

symbols = Dict{Symbol,Ptr{Void}}(:_foo=>C_NULL)
buf = DyldExport.create_image(symbols)
data = takebuf_array(buf)
name = tempname()
open(name,"w") do f
write(f,data)
end
println("Loading Library")
handle = Libdl.dlopen(name)
@show Libdl.dlsym(handle,"foo")
println("Done")

cglobal(:foo)
