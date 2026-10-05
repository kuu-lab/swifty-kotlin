/// Synthetic stubs for kotlin.Function0..N type hierarchy.
///
/// Kept separate from the source-backed migration buckets because
/// Function0..22 are compiler-known residual interfaces.
extension DataFlowSemaPhase {
    func registerSyntheticFunctionTypes(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin.Function パッケージ階層の確立
        let kotlinFunctionPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("Function")],
            symbols: symbols
        )

        // Function0-22 のインターフェースを登録
        for arity in 0...22 {
            registerSyntheticFunctionInterface(
                arity: arity,
                packageFQName: kotlinFunctionPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

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

        // パラメータ型 P1-P22 (in変位)
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

        // 戻り値型パラメータ R (out変位) は宣言順の最後
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

        // 型パラメータの変位指定を設定: [in P1, .., in PN, out R]
        var variances: [TypeVariance] = []
        if arity > 0 {
            for _ in 1...arity {
                variances.append(.in) // パラメータはin
            }
        }
        variances.append(.out) // 戻り値はout
        types.setNominalTypeParameterSymbols(typeParamSymbols, for: interfaceSymbol)
        types.setNominalTypeParameterVariances(variances, for: interfaceSymbol)

        // invokeメソッドの登録
        registerSyntheticFunctionInvokeMethod(
            ownerSymbol: interfaceSymbol,
            arity: arity,
            typeParamSymbols: typeParamSymbols,
            interfaceFQName: interfaceFQName,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerSyntheticFunctionInvokeMethod(
        ownerSymbol: SymbolID,
        arity: Int,
        typeParamSymbols: [SymbolID],
        interfaceFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let invokeName = interner.intern("invoke")
        let invokeFQName = interfaceFQName + [invokeName]

        let invokeSymbol = symbols.define(
            kind: .function,
            name: invokeName,
            fqName: invokeFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        symbols.setParentSymbol(ownerSymbol, for: invokeSymbol)
        let invokeLinkName = arity == 0 || (2 ... 5).contains(arity)
            ? "kk_function_invoke_\(arity)" : "kk_function_invoke"
        symbols.setExternalLinkName(invokeLinkName, for: invokeSymbol)

        // パラメータ型の構築
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

        // レシーバ型の構築
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
