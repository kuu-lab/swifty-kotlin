extension JVMClasspathIndex {
    func bindJDKResourceMethods(in context: CompilationContext, sema: SemaModule) {
        let interner = context.interner
        let symbols = sema.symbols
        let types = sema.types
        let urlPath = ["java", "net", "URL"].map(interner.intern)
        guard classes["java/net/URL"] != nil, let url = symbols.lookup(fqName: urlPath) else { return }
        let resultType = types.make(.classType(ClassType(classSymbol: url, args: [], nullability: .platformType)))

        // Class has a bundled reflection declaration, and ClassLoader has a
        // native resource stub. Bind both to the real classpath method on JVM.
        for name in ["Class", "ClassLoader"] {
            let ownerPath = ["java", "lang", name].map(interner.intern)
            guard let owner = symbols.lookup(fqName: ownerPath),
                  let method = classes["java/lang/" + name]?.methods.first(where: {
                      $0.name == "getResource" && !$0.isStatic && $0.descriptor == "(Ljava/lang/String;)Ljava/net/URL;"
                  }) else { continue }
            let typeParameters = types.nominalTypeParameterSymbols(for: owner)
            let arguments = typeParameters.map { parameter in
                TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nonNull))))
            }
            let receiver = types.make(.classType(ClassType(classSymbol: owner, args: arguments, nullability: .nonNull)))
            let symbol = registerSyntheticFunctionStub(
                named: method.name,
                ownerFQName: ownerPath,
                parentSymbol: owner,
                receiverType: receiver,
                parameters: syntheticFunctionParameters([("name", types.stringType)]),
                returnType: resultType,
                externalLinkName: "",
                typeParameterSymbols: typeParameters,
                classTypeParameterCount: typeParameters.count,
                updateExistingSignature: true,
                symbols: symbols,
                interner: interner
            )
            if symbol != .invalid { setMethod(method, for: symbol) }
        }
    }
}
