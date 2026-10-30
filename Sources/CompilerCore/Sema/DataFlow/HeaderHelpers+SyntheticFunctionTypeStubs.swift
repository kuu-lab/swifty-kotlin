/// Synthetic stubs for the kotlin.Function0..Function255 type hierarchy.
///
/// Function0..22 are registered eagerly for compatibility. Higher arities are
/// materialized on demand so unused invoke signatures do not inflate every Sema run.
extension DataFlowSemaPhase {
    func registerSyntheticFunctionTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinFunctionPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("Function")],
            symbols: symbols
        )

        for arity in 0...22 {
            registerSyntheticFunctionInterface(
                arity: arity,
                packageFQName: kotlinFunctionPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        registerSyntheticSuspendFunctionTypes(symbols: symbols, types: types, interner: interner)
    }

    func ensureSyntheticFunctionInterface(
        arity: Int,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID? {
        guard (0...255).contains(arity) else { return nil }
        if let interfaceSymbol = types.functionNInterfaceSymbols[arity] {
            return interfaceSymbol
        }

        let packageFQName = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("Function")],
            symbols: symbols
        )
        registerSyntheticFunctionInterface(
            arity: arity,
            packageFQName: packageFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
        return types.functionNInterfaceSymbols[arity]
    }

    func registerSyntheticSuspendFunctionTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let coroutinePackage = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("coroutines")],
            symbols: symbols
        )
        let suspendFunctionSymbol = ensureInterfaceSymbol(
            named: "SuspendFunction",
            in: coroutinePackage,
            symbols: symbols,
            interner: interner
        )

        for arity in 0...22 {
            registerSyntheticSuspendFunctionInterface(
                arity: arity,
                packageFQName: coroutinePackage,
                suspendFunctionSymbol: suspendFunctionSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func registerSyntheticSuspendFunctionInterface(
        arity: Int,
        packageFQName: [InternedString],
        suspendFunctionSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("SuspendFunction\(arity)")
        let interfaceFQName = packageFQName + [interfaceName]
        let interfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: interfaceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: interfaceName,
                fqName: interfaceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }
        symbols.insertFlags([.synthetic, .abstractType], for: interfaceSymbol)
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: interfaceSymbol)
        }
        types.suspendFunctionNInterfaceSymbols[arity] = interfaceSymbol

        var typeParamSymbols: [SymbolID] = []
        if arity > 0 {
            for index in 1...arity {
                let name = interner.intern("P\(index)")
                let symbol = symbols.define(
                    kind: .typeParameter,
                    name: name,
                    fqName: interfaceFQName + [name],
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                symbols.setParentSymbol(interfaceSymbol, for: symbol)
                typeParamSymbols.append(symbol)
            }
        }

        let returnName = interner.intern("R")
        let returnSymbol = symbols.define(
            kind: .typeParameter,
            name: returnName,
            fqName: interfaceFQName + [returnName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(interfaceSymbol, for: returnSymbol)
        typeParamSymbols.append(returnSymbol)
        let returnType = types.make(.typeParam(TypeParamType(
            symbol: returnSymbol,
            nullability: .nonNull
        )))

        let variances = Array(repeating: TypeVariance.in, count: arity) + [.out]
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: interfaceSymbol)
        types.setNominalTypeParameterVariances(variances, for: interfaceSymbol)

        symbols.setDirectSupertypes([suspendFunctionSymbol], for: interfaceSymbol)
        symbols.setSupertypeTypeArgs([.out(returnType)], for: interfaceSymbol, supertype: suspendFunctionSymbol)
        types.setNominalDirectSupertypes([suspendFunctionSymbol], for: interfaceSymbol)

        registerSyntheticFunctionInvokeMethod(
            ownerSymbol: interfaceSymbol,
            arity: arity,
            typeParamSymbols: typeParamSymbols,
            interfaceFQName: interfaceFQName,
            symbols: symbols,
            types: types,
            interner: interner,
            isSuspend: true,
            isAbstract: true,
            usesRuntimeInvokeBridge: arity <= 6
        )
    }

    func registerSyntheticFunctionInterface(
        arity: Int,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let interfaceName = interner.intern("Function\(arity)")
        let interfaceFQName = packageFQName + [interfaceName]

        // STDLIB-SHARED-013: The interface may have been imported as a synthetic
        // nominal anchor, but its `invoke` method and type parameters are not
        // serialized. Re-register the members even when the interface exists.
        let interfaceSymbol: SymbolID = if let existing = symbols.lookup(fqName: interfaceFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: interfaceName,
                fqName: interfaceFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        // 関数型 ⇔ FunctionN のサブタイプ判定が名前解決を要しないよう、
        // arity → symbol を TypeSystem に登録する（KUU-1084）。
        types.functionNInterfaceSymbols[arity] = interfaceSymbol

        // 型パラメータの定義。KUU-1084: Kotlin と同じ [P1..PN, R] の宣言順で
        // 登録する — `Function1<Int, String>` が書かれた順に (Int) -> String
        // を意味するようにする（以前は [R, P...] 順で、書かれた型引数と
        // invoke のシグネチャが逆順に束縛されていた）。
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []

        if arity > 0 {
            for i in 1...arity {
                let paramName = interner.intern("P\(i)")
                let paramFQName = interfaceFQName + [paramName]
                let paramSymbol = symbols.define(
                    kind: .typeParameter,
                    name: paramName,
                    fqName: paramFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: []
                )
                typeParamSymbols.append(paramSymbol)
                typeParamTypes.append(types.make(.typeParam(TypeParamType(
                    symbol: paramSymbol,
                    nullability: .nonNull
                ))))
            }
        }

        let returnParamName = interner.intern("R")
        let returnParamFQName = interfaceFQName + [returnParamName]
        let returnParamSymbol = symbols.define(
            kind: .typeParameter,
            name: returnParamName,
            fqName: returnParamFQName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
        typeParamSymbols.append(returnParamSymbol)
        typeParamTypes.append(types.make(.typeParam(TypeParamType(
            symbol: returnParamSymbol,
            nullability: .nonNull
        ))))

        var variances: [TypeVariance] = []
        if arity > 0 {
            for _ in 1...arity {
                variances.append(.in)
            }
        }
        variances.append(.out)
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: interfaceSymbol)
        types.setNominalTypeParameterVariances(variances, for: interfaceSymbol)

        registerSyntheticFunctionInvokeMethod(
            ownerSymbol: interfaceSymbol,
            arity: arity,
            typeParamSymbols: typeParamSymbols,
            interfaceFQName: interfaceFQName,
            symbols: symbols,
            types: types,
            interner: interner,
            isAbstract: true,
            usesRuntimeInvokeBridge: arity <= 22
        )
    }

    func registerSyntheticFunctionInvokeMethod(
        ownerSymbol: SymbolID,
        arity: Int,
        typeParamSymbols: [SymbolID],
        interfaceFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        isSuspend: Bool = false,
        isAbstract: Bool = false,
        usesRuntimeInvokeBridge: Bool = true
    ) {
        let invokeName = interner.intern("invoke")
        let invokeFQName = interfaceFQName + [invokeName]

        var invokeFlags: SymbolFlags = [.synthetic, .operatorFunction]
        if isAbstract {
            invokeFlags.insert(.abstractType)
        }
        let invokeSymbol = symbols.define(
            kind: .function,
            name: invokeName,
            fqName: invokeFQName,
            declSite: nil,
            visibility: .public,
            // SAM discovery must see the compiler-known invoke as an abstract member.
            flags: invokeFlags
        )
        symbols.setParentSymbol(ownerSymbol, for: invokeSymbol)
        if usesRuntimeInvokeBridge {
            let runtimeInvoke: String = if isSuspend {
                arity == 1 ? "kk_suspend_function_invoke" : "kk_suspend_function_invoke_\(arity)"
            } else {
                arity == 1 ? "kk_function_invoke" : "kk_function_invoke_\(arity)"
            }
            symbols.setExternalLinkName(runtimeInvoke, for: invokeSymbol)
        }

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        if arity > 0 {
            for i in 1...arity {
                // [P1..PN, R] 宣言順では P_i は typeParamSymbols[i - 1]
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbols[i - 1],
                    nullability: .nonNull
                )))
                parameterTypes.append(paramType)

                let paramName = interner.intern("p\(i)")
                let paramSymbol = symbols.define(
                    kind: .valueParameter,
                    name: paramName,
                    fqName: invokeFQName + [paramName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(invokeSymbol, for: paramSymbol)
                parameterSymbols.append(paramSymbol)
            }
        }

        let returnType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbols[arity], // R は宣言順の最後
            nullability: .nonNull
        )))

        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: typeParamSymbols.enumerated().map { index, symbol in
                let variance: TypeVariance = index == arity ? .out : .in
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: symbol,
                    nullability: .nonNull
                )))
                switch variance {
                case .out: return .out(paramType)
                case .in: return .in(paramType)
                case .invariant: return .invariant(paramType)
                }
            },
            nullability: .nonNull
        )))

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: arity),
                valueParameterIsVararg: Array(repeating: false, count: arity),
                typeParameterSymbols: typeParamSymbols,
                classTypeParameterCount: typeParamSymbols.count
            ),
            for: invokeSymbol
        )
    }

}
