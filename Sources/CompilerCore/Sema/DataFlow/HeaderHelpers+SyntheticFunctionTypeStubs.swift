/// Synthetic stubs for kotlin.Function0..N type hierarchy.
///
/// Split out from `HeaderHelpers+SyntheticTODOAndIOStubs.swift` to keep
/// each header-helpers file scoped to a single responsibility.
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

        // 既に存在する場合はスキップ
        if symbols.lookup(fqName: interfaceFQName) != nil {
            return
        }

        let interfaceSymbol = symbols.define(
            kind: .interface,
            name: interfaceName,
            fqName: interfaceFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )

        // 型パラメータの定義
        var typeParamSymbols: [SymbolID] = []
        var typeParamTypes: [TypeID] = []

        // 戻り値型パラメータ R (out変位)
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

        // 型パラメータの変位指定を設定
        var variances: [TypeVariance] = [.out] // 戻り値はout
        if arity > 0 {
            for _ in 1...arity {
                variances.append(.in) // パラメータはin
            }
        }
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
        symbols.setExternalLinkName("kk_function_invoke", for: invokeSymbol)

        // パラメータ型の構築
        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        if arity > 0 {
            for i in 1...arity {
                let paramType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbols[i],
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
            symbol: typeParamSymbols[0], // R
            nullability: .nonNull
        )))

        // レシーバ型の構築
        let receiverType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: typeParamSymbols.enumerated().map { index, symbol in
                let variance: TypeVariance = index == 0 ? .out : .in
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
