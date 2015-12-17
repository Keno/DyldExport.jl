module DyldExport

using MachO
using StrPack

# Constants we'll need
import MachO: N_EXT, N_ABS, NO_SECT,
    MH_MAGIC_64, CPU_TYPE_X86_64, MH_DYLIB, MH_NOUNDEFS,
    LC_SYMTAB, LC_DYSYMTAB, LC_SEGMENT_64, MH_BUNDLE

# And datastructures we'll need
import MachO: mach_header_64, nlist_64, symtab_command, dysymtab_command,
    segment_command_64

if OS_NAME != :Darwin
    error("Currently only supported on OS X")
end

function create_sections(symbols::Dict{Symbol,Ptr{Void}})
    symtab = IOBuffer()
    strtab = IOBuffer()
    for (name,value) in symbols
        sym = nlist_64(
            position(strtab), # n_strx
            N_ABS,    # n_type
            NO_SECT,          # n_sect
            0,                # n_desc
            value)            # n_value
        pack(symtab, sym)
        write(strtab, name)
        write(strtab, UInt8('\0'))
    end
    symtab, strtab
end

function create_image(symbols::Dict{Symbol,Ptr{Void}})
    buf = IOBuffer()
    symtab, strtab = create_sections(symbols)

    # Write dummy versions of everything so we know
    # the offsets
    lcssize = 8*sizeof(UInt32)+sizeof(symtab_command)+sizeof(dysymtab_command)+
        2*sizeof(segment_command_64)
    pack(buf, mach_header_64(
        MH_MAGIC_64,     # magic
        CPU_TYPE_X86_64, # cputype
        0,               # cpusubtype
        MH_BUNDLE,       # filetype
        4,               # ncmds
        # sizeofcmds
        lcssize,
        MH_NOUNDEFS,    # flags
    ))

    lcpos = position(buf)

    # Needs a dummy writable segment, which is also named __TEXT and at least
    # one byte large (or dyld crashes - filed as radar 23944790)
    write(buf, UInt32(LC_SEGMENT_64))
    write(buf, UInt32(sizeof(segment_command_64)+2*sizeof(UInt32)))
    pack(buf, segment_command_64(
        MachO.small_fixed_string(reinterpret(UInt128,UInt8['_','_','T','E','X','T',0,0,0,0,0,0,0,0,0,0])[]),
        0,4096,0,lcpos+lcssize,0x2,0x2,0,0
    ))

    write(buf, UInt32(LC_SEGMENT_64))
    write(buf, UInt32(sizeof(segment_command_64)+2*sizeof(UInt32)))
    pack(buf, segment_command_64(
        MachO.small_fixed_string(reinterpret(UInt128,UInt8['_','_','L','I','N','K','E','D','I','T',0,0,0,0,0,0])[]),
        4096,8192,0,4096,0x1,0x1,0,0
    ))


    write(buf, UInt32(LC_SYMTAB))
    write(buf, UInt32(sizeof(symtab_command)+2*sizeof(UInt32)))
    symtablc_offs = position(buf)
    pack(buf, symtab_command())

    write(buf, UInt32(LC_DYSYMTAB))
    write(buf, UInt32(sizeof(dysymtab_command)+2*sizeof(UInt32)))
    pack(buf, dysymtab_command(
        0,               # ilocalsym
        0,               # nlocalsym
        0,               # iextdefsym
        length(symbols), # nextdefsym
        0,               # iundefsym
        0,               # nundefsym
        0,               # tocoff
        0,               # ntoc
        0,               # modtaboff
        0,               # nmodtab
        0,               # extrefsymoff
        0,               # nextrefsyms
        0,               # indirectsymoff
        0,               # nindirectsyms
        0,               # extreloff
        0,               # nextrel
        0,               # locreloff
        0,               # nlocrel
    ))

    symtab_offs = position(buf)
    write(buf, takebuf_array(symtab))

    strtab_offs = position(buf)
    data = takebuf_array(strtab)
    strtab_size = sizeof(data)
    write(buf, data)

    seek(buf, symtablc_offs)
    pack(buf, symtab_command(
        symtab_offs,
        length(symbols),
        strtab_offs,
        strtab_size
    ))

    seekend(buf)

    # Pad the file
    write(buf, zeros(4096-position(buf)))

    buf
end

const NSObjectFileImageFailure = 0
const NSObjectFileImageSuccess = 1
const NSObjectFileImageInappropriateFile = 2
const NSObjectFileImageArch = 3
const NSObjectFileImageFormat = 4
const NSObjectFileImageAccess = 5

function NSCreateObjectFileImageFromMemory(data)
    out = Ref{Ptr{Void}}()
    ret = ccall(:NSCreateObjectFileImageFromMemory,Cint,
        (Ptr{Void},Csize_t,Ref{Ptr{Void}}),pointer(data),sizeof(data),out)
    if ret != NSObjectFileImageSuccess
        error("Failed to open object file")
    end
    out[]
end

end # module
