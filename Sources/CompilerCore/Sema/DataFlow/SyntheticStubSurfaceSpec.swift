
indirect enum SyntheticStubTypeRef: Hashable, Sendable {
    case typeID(TypeID)
    case builtin(SyntheticStubBuiltinType)
    case nullable(SyntheticStubTypeRef)
    case classType(fqName: [String], args: [SyntheticStubTypeArg], nullability: Nullability)
    case typeParameter(name: String, nullability: Nullability)
    case fallback(primary: SyntheticStubTypeRef, fallback: SyntheticStubTypeRef)

    static let unit: SyntheticStubTypeRef = .builtin(.unit)
    static let boolean: SyntheticStubTypeRef = .builtin(.boolean)
    static let char: SyntheticStubTypeRef = .builtin(.char)
    static let int: SyntheticStubTypeRef = .builtin(.int)
    static let double: SyntheticStubTypeRef = .builtin(.double)
    static let string: SyntheticStubTypeRef = .builtin(.string)

    static func namedClass(
        _ fqName: [String],
        args: [SyntheticStubTypeArg] = [],
        nullability: Nullability = .nonNull
    ) -> SyntheticStubTypeRef {
        .classType(fqName: fqName, args: args, nullability: nullability)
    }

    static func typeParameter(
        _ name: String,
        nullability: Nullability = .nonNull
    ) -> SyntheticStubTypeRef {
        .typeParameter(name: name, nullability: nullability)
    }
}

enum SyntheticStubBuiltinType: Hashable, Sendable {
    case error
    case unit
    case nothing
    case any
    case boolean
    case char
    case int
    case long
    case float
    case double
    case string
    case uint
    case ulong
    case ubyte
    case ushort
}

indirect enum SyntheticStubTypeArg: Hashable, Sendable {
    case invariant(SyntheticStubTypeRef)
    case out(SyntheticStubTypeRef)
    case `in`(SyntheticStubTypeRef)
    case star
}

struct SyntheticStubParameterSpec: Hashable, Sendable {
    let name: String
    let type: SyntheticStubTypeRef
    let hasDefault: Bool
    let isVararg: Bool

    init(
        name: String,
        type: SyntheticStubTypeRef,
        hasDefault: Bool = false,
        isVararg: Bool = false
    ) {
        self.name = name
        self.type = type
        self.hasDefault = hasDefault
        self.isVararg = isVararg
    }
}

struct SyntheticFunctionStubSpec: Sendable {
    let name: String
    let externalLinkName: String?
    let receiverType: SyntheticStubTypeRef?
    let parameters: [SyntheticStubParameterSpec]
    let returnType: SyntheticStubTypeRef
    let visibility: Visibility
    let flags: SymbolFlags
    let canThrow: Bool
    let typeParameterNames: [String]
    let typeParameterUpperBounds: [[SyntheticStubTypeRef]]
    let classTypeParameterCount: Int

    init(
        name: String,
        externalLinkName: String? = nil,
        receiverType: SyntheticStubTypeRef? = nil,
        parameters: [SyntheticStubParameterSpec] = [],
        returnType: SyntheticStubTypeRef,
        visibility: Visibility = .public,
        flags: SymbolFlags = [.synthetic],
        canThrow: Bool = false,
        typeParameterNames: [String] = [],
        typeParameterUpperBounds: [[SyntheticStubTypeRef]] = [],
        classTypeParameterCount: Int = 0
    ) {
        self.name = name
        self.externalLinkName = externalLinkName
        self.receiverType = receiverType
        self.parameters = parameters
        self.returnType = returnType
        self.visibility = visibility
        self.flags = flags
        self.canThrow = canThrow
        self.typeParameterNames = typeParameterNames
        self.typeParameterUpperBounds = typeParameterUpperBounds
        self.classTypeParameterCount = classTypeParameterCount
    }
}

struct SyntheticConstructorStubSpec: Sendable {
    let externalLinkName: String?
    let parameters: [SyntheticStubParameterSpec]
    let visibility: Visibility
    let flags: SymbolFlags
    let typeParameterNames: [String]
    let typeParameterUpperBounds: [[SyntheticStubTypeRef]]
    let classTypeParameterCount: Int

    init(
        externalLinkName: String? = nil,
        parameters: [SyntheticStubParameterSpec] = [],
        visibility: Visibility = .public,
        flags: SymbolFlags = [.synthetic],
        typeParameterNames: [String] = [],
        typeParameterUpperBounds: [[SyntheticStubTypeRef]] = [],
        classTypeParameterCount: Int = 0
    ) {
        self.externalLinkName = externalLinkName
        self.parameters = parameters
        self.visibility = visibility
        self.flags = flags
        self.typeParameterNames = typeParameterNames
        self.typeParameterUpperBounds = typeParameterUpperBounds
        self.classTypeParameterCount = classTypeParameterCount
    }
}


struct SyntheticStubRegistrationContext {
    let ownerFQName: [InternedString]
    let parentSymbol: SymbolID?
    let typeParameterSymbolsByName: [String: SymbolID]
    let bundledIndex: BundledDeclarationIndex
    let skipStats: SyntheticStubSkipStatsCollector?

    init(
        ownerFQName: [InternedString],
        parentSymbol: SymbolID? = nil,
        typeParameterSymbolsByName: [String: SymbolID] = [:],
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        self.ownerFQName = ownerFQName
        self.parentSymbol = parentSymbol
        self.typeParameterSymbolsByName = typeParameterSymbolsByName
        self.bundledIndex = bundledIndex
        self.skipStats = skipStats
    }
}

extension DataFlowSemaPhase {
    @discardableResult
    func registerSyntheticFunctionStubs(
        _ specs: [SyntheticFunctionStubSpec],
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [SymbolID] {
        specs.compactMap { spec in
            registerSyntheticFunctionStub(
                spec,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    @discardableResult
    func registerSyntheticConstructorStubs(
        _ specs: [SyntheticConstructorStubSpec],
        ownerType: SyntheticStubTypeRef,
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [SymbolID] {
        specs.compactMap { spec in
            registerSyntheticConstructorStub(
                spec,
                ownerType: ownerType,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    @discardableResult
    private func registerSyntheticConstructorStub(
        _ spec: SyntheticConstructorStubSpec,
        ownerType ownerTypeRef: SyntheticStubTypeRef,
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID? {
        guard let ownerType = resolveSyntheticStubType(
            ownerTypeRef,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }

        guard let parameters = resolveSyntheticStubParameters(
            spec.parameters,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }
        guard let (typeParameterSymbols, upperBounds) = resolveSyntheticStubTypeParameters(
            names: spec.typeParameterNames,
            upperBoundRefs: spec.typeParameterUpperBounds,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }

        let constructorName = interner.intern("<init>")
        let constructorFQName = context.ownerFQName + [constructorName]
        let parameterTypes = parameters.map(\.type)
        if symbols.deferWorkUntilImportedMemberMaterializes(at: constructorFQName, work: { [self] in
            _ = registerSyntheticConstructorStub(
                spec,
                ownerType: ownerTypeRef,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }) {
            return nil
        }
        if let existing = symbols.lookupAll(fqName: constructorFQName).first(where: { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
                && signature.returnType == ownerType
        }) {
            if let externalLinkName = spec.externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            return existing
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: constructorName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: spec.visibility,
            flags: spec.flags
        )
        if let parentSymbol = context.parentSymbol, parentSymbol != .invalid {
            symbols.setParentSymbol(parentSymbol, for: constructorSymbol)
        }
        if let externalLinkName = spec.externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: constructorSymbol)
        }

        let valueParameterSymbols = defineSyntheticStubValueParameters(
            parameters,
            ownerSymbol: constructorSymbol,
            ownerFQName: constructorFQName,
            symbols: symbols,
            interner: interner
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: parameters.map(\.isVararg),
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: upperBounds,
                classTypeParameterCount: spec.classTypeParameterCount
            ),
            for: constructorSymbol
        )
        return constructorSymbol
    }

    @discardableResult
    private func registerSyntheticFunctionStub(
        _ spec: SyntheticFunctionStubSpec,
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID? {
        let receiverType: TypeID?
        if let receiverRef = spec.receiverType {
            guard let resolvedReceiver = resolveSyntheticStubType(
                receiverRef,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            ) else {
                return nil
            }
            receiverType = resolvedReceiver
        } else {
            receiverType = nil
        }

        guard let returnType = resolveSyntheticStubType(
            spec.returnType,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }

        guard let parameters = resolveSyntheticStubParameters(
            spec.parameters,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }
        guard let (typeParameterSymbols, upperBounds) = resolveSyntheticStubTypeParameters(
            names: spec.typeParameterNames,
            upperBoundRefs: spec.typeParameterUpperBounds,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        ) else {
            return nil
        }

        if let externalLinkName = spec.externalLinkName, spec.visibility == .public {
            return CompilerCore.registerSyntheticFunctionStub(
                named: spec.name,
                ownerFQName: context.ownerFQName,
                parentSymbol: context.parentSymbol,
                receiverType: receiverType,
                parameters: parameters,
                returnType: returnType,
                externalLinkName: externalLinkName,
                flags: spec.flags,
                canThrow: spec.canThrow,
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: upperBounds,
                classTypeParameterCount: spec.classTypeParameterCount,
                matchReturnType: true,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats,
                types: types,
                symbols: symbols,
                interner: interner
            )
        }

        return registerSyntheticFunctionDeclaration(
            spec,
            context: context,
            receiverType: receiverType,
            parameters: parameters,
            returnType: returnType,
            typeParameterSymbols: typeParameterSymbols,
            typeParameterUpperBoundsList: upperBounds,
            symbols: symbols,
            interner: interner
        )
    }

    @discardableResult
    private func registerSyntheticFunctionDeclaration(
        _ spec: SyntheticFunctionStubSpec,
        context: SyntheticStubRegistrationContext,
        receiverType: TypeID?,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        typeParameterSymbols: [SymbolID],
        typeParameterUpperBoundsList: [[TypeID]],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let functionName = interner.intern(spec.name)
        let functionFQName = context.ownerFQName + [functionName]
        let parameterTypes = parameters.map(\.type)

        if symbols.deferWorkUntilImportedMemberMaterializes(at: functionFQName, work: { [self] in
            _ = registerSyntheticFunctionDeclaration(
                spec,
                context: context,
                receiverType: receiverType,
                parameters: parameters,
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                symbols: symbols,
                interner: interner
            )
        }) {
            return nil
        }
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
        }) {
            if let externalLinkName = spec.externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            return existing
        }

        if shouldSkipSyntheticStub(
            bundledIndex: context.bundledIndex,
            ownerFQName: context.ownerFQName,
            name: functionName,
            arity: parameterTypes.count
        ) {
            context.skipStats?.recordSkip(
                ownerFQName: context.ownerFQName,
                name: functionName,
                arity: parameterTypes.count,
                interner: interner
            )
            return .invalid
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: spec.visibility,
            flags: spec.flags
        )
        if let parentSymbol = context.parentSymbol, parentSymbol != .invalid {
            symbols.setParentSymbol(parentSymbol, for: functionSymbol)
        }
        if let externalLinkName = spec.externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }

        let valueParameterSymbols = defineSyntheticStubValueParameters(
            parameters,
            ownerSymbol: functionSymbol,
            ownerFQName: functionFQName,
            symbols: symbols,
            interner: interner
        )

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                canThrow: spec.canThrow,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: parameters.map(\.isVararg),
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                classTypeParameterCount: spec.classTypeParameterCount
            ),
            for: functionSymbol
        )
        return functionSymbol
    }


    private func resolveSyntheticStubType(
        _ ref: SyntheticStubTypeRef,
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        switch ref {
        case let .typeID(typeID):
            return typeID
        case let .builtin(builtin):
            return resolveSyntheticStubBuiltinType(builtin, types: types)
        case let .nullable(inner):
            return resolveSyntheticStubType(
                inner,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            ).map(types.makeNullable)
        case let .classType(fqName, args, nullability):
            let internedFQName = fqName.map(interner.intern)
            guard let classSymbol = symbols.lookup(fqName: internedFQName) else {
                return nil
            }
            let resolvedArgs = resolveSyntheticStubTypeArgs(
                args,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            )
            guard resolvedArgs != nil || args.isEmpty else {
                return nil
            }
            return types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: resolvedArgs ?? [],
                nullability: nullability
            )))
        case let .typeParameter(name, nullability):
            guard let symbol = context.typeParameterSymbolsByName[name] else {
                return nil
            }
            return types.make(.typeParam(TypeParamType(
                symbol: symbol,
                nullability: nullability
            )))
        case let .fallback(primary, fallback):
            return resolveSyntheticStubType(
                primary,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            ) ?? resolveSyntheticStubType(
                fallback,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }

    private func resolveSyntheticStubBuiltinType(
        _ builtin: SyntheticStubBuiltinType,
        types: TypeSystem
    ) -> TypeID {
        switch builtin {
        case .error:
            types.errorType
        case .unit:
            types.unitType
        case .nothing:
            types.nothingType
        case .any:
            types.anyType
        case .boolean:
            types.booleanType
        case .char:
            types.charType
        case .int:
            types.intType
        case .long:
            types.longType
        case .float:
            types.floatType
        case .double:
            types.doubleType
        case .string:
            types.stringType
        case .uint:
            types.uintType
        case .ulong:
            types.ulongType
        case .ubyte:
            types.ubyteType
        case .ushort:
            types.ushortType
        }
    }

    private func resolveSyntheticStubTypeArgs(
        _ args: [SyntheticStubTypeArg],
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [TypeArg]? {
        var resolved: [TypeArg] = []
        resolved.reserveCapacity(args.count)
        for arg in args {
            switch arg {
            case let .invariant(ref):
                guard let type = resolveSyntheticStubType(
                    ref,
                    context: context,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) else {
                    return nil
                }
                resolved.append(.invariant(type))
            case let .out(ref):
                guard let type = resolveSyntheticStubType(
                    ref,
                    context: context,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) else {
                    return nil
                }
                resolved.append(.out(type))
            case let .in(ref):
                guard let type = resolveSyntheticStubType(
                    ref,
                    context: context,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) else {
                    return nil
                }
                resolved.append(.in(type))
            case .star:
                resolved.append(.star)
            }
        }
        return resolved
    }

    private func resolveSyntheticStubTypeParameterUpperBounds(
        _ upperBounds: [[SyntheticStubTypeRef]],
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [[TypeID]]? {
        var resolvedBounds: [[TypeID]] = []
        resolvedBounds.reserveCapacity(upperBounds.count)
        for bounds in upperBounds {
            var resolved: [TypeID] = []
            resolved.reserveCapacity(bounds.count)
            for bound in bounds {
                guard let type = resolveSyntheticStubType(
                    bound,
                    context: context,
                    symbols: symbols,
                    types: types,
                    interner: interner
                ) else {
                    return nil
                }
                resolved.append(type)
            }
            resolvedBounds.append(resolved)
        }
        return resolvedBounds
    }

    private func resolveSyntheticStubParameters(
        _ specParameters: [SyntheticStubParameterSpec],
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)]? {
        var parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)] = []
        parameters.reserveCapacity(specParameters.count)
        for parameter in specParameters {
            guard let parameterType = resolveSyntheticStubType(
                parameter.type,
                context: context,
                symbols: symbols,
                types: types,
                interner: interner
            ) else {
                return nil
            }
            parameters.append((
                name: parameter.name,
                type: parameterType,
                hasDefault: parameter.hasDefault,
                isVararg: parameter.isVararg
            ))
        }
        return parameters
    }

    private func resolveSyntheticStubTypeParameters(
        names: [String],
        upperBoundRefs: [[SyntheticStubTypeRef]],
        context: SyntheticStubRegistrationContext,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> (typeParameterSymbols: [SymbolID], upperBounds: [[TypeID]])? {
        let typeParameterSymbols = names.compactMap {
            context.typeParameterSymbolsByName[$0]
        }
        guard typeParameterSymbols.count == names.count else {
            return nil
        }
        let upperBounds = resolveSyntheticStubTypeParameterUpperBounds(
            upperBoundRefs,
            context: context,
            symbols: symbols,
            types: types,
            interner: interner
        )
        guard upperBounds != nil || upperBoundRefs.isEmpty else {
            return nil
        }
        return (typeParameterSymbols, upperBounds ?? [])
    }

    private func defineSyntheticStubValueParameters(
        _ parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SymbolID] {
        var valueParameterSymbols: [SymbolID] = []
        valueParameterSymbols.reserveCapacity(parameters.count)
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ownerFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ownerSymbol, for: parameterSymbol)
            valueParameterSymbols.append(parameterSymbol)
        }
        return valueParameterSymbols
    }
}
