using Cxx
include(Pkg.dir("Cxx","test","llvmincludes.jl"))
function collectSymbolsForExport(RD::pcpp"clang::CXXRecordDecl")
    C = Cxx.instance(Cxx.__default_compiler__)
    f = Cxx.CreateFunctionWithPersonality(C, Cxx.julia_to_llvm(Void),[Cxx.julia_to_llvm(Ptr{Ptr{Void}})])
    state = Cxx.setup_cpp_env(C,f)
    builder = Cxx.irbuilder(C)
    names = Symbol[]
    nummethods = icxx"""
    auto *CGM = $(C.CGM);
    auto *RD = clang::cast<clang::CXXRecordDecl>($RD->getDefinition());
    assert(RD);
    RD->dump();
    CGM->EmitTopLevelDecl(RD);
    llvm::SmallVector<llvm::Constant *, 0> addresses;
    unsigned i = 0;
    clang::CodeGen::CGBuilderTy *builder = $builder;
    for (auto method : RD->methods()) {
        clang::GlobalDecl GD;
        if (clang::isa<clang::CXXConstructorDecl>(method))
            GD = clang::GlobalDecl(clang::cast<clang::CXXConstructorDecl>(method),clang::Ctor_Complete);
        else if (clang::isa<clang::CXXDestructorDecl>(method))
            GD = clang::GlobalDecl(clang::cast<clang::CXXDestructorDecl>(method),clang::Dtor_Complete);
        else
            GD = clang::GlobalDecl(method);
        auto name = CGM->getMangledName(GD);
        $:(push!(names,symbol(bytestring(icxx"return name.data();"))));
        auto llvmf = CGM->GetAddrOfGlobal(GD,false);
        if (clang::cast<llvm::Function>(llvmf)->isDeclaration())
            continue;
        llvm::Value *Val =
          builder->CreateBitCast(llvmf,$(Cxx.julia_to_llvm(Ptr{Void})));
        llvm::Value *Addr = builder->CreateConstGEP1_32($(Cxx.julia_to_llvm(Ptr{Void})),
          &$f->getArgumentList().front(), i++);
        builder->CreateStore(Val,
          clang::CodeGen::Address(Addr,clang::CharUnits(8)));
    }
    builder->CreateRetVoid();
    i;
    """
    Cxx.cleanup_cpp_env(C,state)
    addresses = Array(Ptr{Void},nummethods)
    eval(:(Core.Intrinsics.llvmcall($(f.ptr),Void,Tuple{Ptr{Ptr{Void}}},$(pointer(addresses)))))
    symbols = Dict{Symbol,Ptr{Void}}()
    for (k,v) in zip(names,addresses)
        symbols[k] = v
    end
    symbols
end

export_class(RD::pcpp"clang::CXXRecordDecl") = export_symbols(collectSymbolsForExport(RD))
