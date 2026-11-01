
extension TypeCheckHelpers {
    func samMethodSignature(
        for interfaceSymbol: SymbolID,
        sema: SemaModule
    ) -> FunctionSignature? {
        guard let sym = sema.symbols.symbol(interfaceSymbol),
              sym.kind == .interface,
              sym.flags.contains(.funInterface)
        else {
            return nil
        }
        guard let method = effectiveSamAbstractMethod(for: interfaceSymbol, symbols: sema.symbols) else {
            return nil
        }
        return sema.symbols.functionSignature(for: method)
    }

    /// The single abstract function a `fun interface` effectively requires,
    /// counting abstract functions inherited from super-interfaces (unless the
    /// interface overrides or implements them). Returns `nil` unless exactly one
    /// such function exists. Abstract properties make the interface non-SAM.
    func effectiveSamAbstractMethod(
        for interfaceSymbol: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        guard symbols.symbol(interfaceSymbol) != nil else { return nil }
        var ownNames: Set<InternedString> = []
        var candidates: [SymbolID] = []
        for childID in symbols.declaredChildren(of: interfaceSymbol) {
            guard let child = symbols.symbol(childID),
                  child.kind == .function || child.kind == .property
            else { continue }
            ownNames.insert(child.name)
            if child.flags.contains(.abstractType) {
                candidates.append(childID)
            }
        }
        for inherited in collectInheritedAbstractMembers(for: interfaceSymbol, symbols: symbols) {
            guard let member = symbols.symbol(inherited),
                  !ownNames.contains(member.name)
            else { continue }
            candidates.append(inherited)
        }
        var functions: [SymbolID] = []
        for candidate in candidates {
            guard let member = symbols.symbol(candidate) else { continue }
            if member.kind == .property { return nil }
            if symbols.functionSignature(for: candidate) != nil {
                functions.append(candidate)
            }
        }
        guard functions.count == 1 else { return nil }
        return functions[0]
    }

    private func ancestorTypeArgs(
        from start: SymbolID,
        args: [TypeArg],
        to owner: SymbolID,
        sema: SemaModule
    ) -> [TypeArg]? {
        var visited: Set<SymbolID> = []
        func walk(_ current: SymbolID, _ currentArgs: [TypeArg]) -> [TypeArg]? {
            if current == owner { return currentArgs }
            guard visited.insert(current).inserted else { return nil }
            let params = sema.types.nominalTypeParameterSymbols(for: current)
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(params)
            var substitution: [TypeVarID: TypeID] = [:]
            if params.count == currentArgs.count {
                for (index, arg) in currentArgs.enumerated() {
                    guard let typeVar = typeVarBySymbol[params[index]] else { continue }
                    switch arg {
                    case let .invariant(type), let .out(type), let .in(type):
                        substitution[typeVar] = type
                    case .star:
                        substitution[typeVar] = sema.types.nullableAnyType
                    }
                }
            }
            for supertype in sema.symbols.directSupertypes(for: current) {
                let mapped = sema.symbols.supertypeTypeArgs(for: current, supertype: supertype).map { arg in
                    arg.mapTypes {
                        sema.types.substituteTypeParameters(
                            in: $0,
                            substitution: substitution,
                            typeVarBySymbol: typeVarBySymbol
                        )
                    }
                }
                if let found = walk(supertype, mapped) { return found }
            }
            return nil
        }
        return walk(start, args)
    }

    func samFunctionType(
        for expectedType: TypeID,
        sema: SemaModule
    ) -> FunctionType? {
        return specializedSamFunctionType(
            for: expectedType, includeMemberExtensionReceiver: true, sema: sema
        )
    }

    /// Receiver-bearing SAMs expose their extension receiver in the function view
    /// used to type-check both lambda literals and callable references.
    func samCallableReferenceFunctionType(
        for expectedType: TypeID,
        sema: SemaModule
    ) -> FunctionType? {
        return specializedSamFunctionType(
            for: expectedType, includeMemberExtensionReceiver: true, sema: sema
        )
    }

    private func specializedSamFunctionType(
        for expectedType: TypeID,
        includeMemberExtensionReceiver: Bool,
        sema: SemaModule
    ) -> FunctionType? {
        guard let classType = resolveClassType(expectedType, sema: sema) else {
            return nil
        }
        guard let interface = sema.symbols.symbol(classType.classSymbol),
              interface.kind == .interface,
              interface.flags.contains(.funInterface),
              let method = effectiveSamAbstractMethod(for: classType.classSymbol, symbols: sema.symbols),
              let signature = sema.symbols.functionSignature(for: method)
        else {
            return nil
        }
        var ownerSymbol = classType.classSymbol
        var ownerArgs = classType.args
        if let method = effectiveSamAbstractMethod(for: classType.classSymbol, symbols: sema.symbols),
           let owner = sema.symbols.parentSymbol(for: method),
           owner != classType.classSymbol
        {
            guard let args = ancestorTypeArgs(
                from: classType.classSymbol,
                args: classType.args,
                to: owner,
                sema: sema
            ) else { return nil }
            ownerSymbol = owner
            ownerArgs = args
        }
        let typeParamSymbols = sema.types.nominalTypeParameterSymbols(for: ownerSymbol)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        if typeParamSymbols.count == ownerArgs.count {
            for (index, arg) in ownerArgs.enumerated() {
                guard index < typeParamSymbols.count,
                      let typeVar = typeVarBySymbol[typeParamSymbols[index]]
                else {
                    continue
                }
                switch arg {
                case let .invariant(type), let .out(type), let .in(type):
                    substitution[typeVar] = type
                case .star:
                    substitution[typeVar] = sema.types.nullableAnyType
                }
            }
        }
        let substitute = { (type: TypeID) -> TypeID in
            let substituted = sema.types.substituteTypeParameters(
                in: type,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if sema.types.nullability(of: substituted) == .platformType {
                return sema.types.makeNonNullable(substituted)
            }
            return substituted
        }
        return FunctionType(
            contextReceivers: signature.contextReceiverTypes.map(substitute),
            receiver: includeMemberExtensionReceiver
                && sema.symbols.memberExtensionOwnerSymbol(for: method) != nil
                ? signature.receiverType.map(substitute)
                : nil,
            params: signature.parameterTypes.map(substitute),
            returnType: substitute(signature.returnType),
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )
    }
}
