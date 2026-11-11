/// A single abstract-member requirement a `fun interface` still owes, seen
/// from the interface itself. Members sharing a name, kind and substituted
/// signature form one requirement — an inherited abstract override and the
/// base declaration it re-abstracts count once, as does the same signature
/// arriving through a diamond (KUU-4360).
private struct SamRequirementKey: Hashable {
    let name: InternedString
    let kind: SymbolKind
    let parameterTypes: [TypeID]
    let extensionReceiverType: TypeID?
    let isSuspend: Bool
}

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
        guard let method = effectiveSamAbstractMethod(for: interfaceSymbol, symbols: sema.symbols, types: sema.types) else {
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
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SymbolID? {
        guard symbols.symbol(interfaceSymbol) != nil else { return nil }
        var coveredKeys: Set<SamRequirementKey> = []
        var candidates: [SymbolID] = []
        for childID in symbols.declaredChildren(of: interfaceSymbol) {
            guard let child = symbols.symbol(childID),
                  child.kind == .function || child.kind == .property
            else { continue }
            if child.flags.contains(.abstractType) {
                candidates.append(childID)
            } else if let key = samRequirementKey(
                for: childID, interface: interfaceSymbol, symbols: symbols, types: types
            ) {
                // A concrete own member leaves no remaining abstract
                // requirement for the same signature (KUU-4360).
                coveredKeys.insert(key)
            }
        }
        candidates.append(contentsOf: collectInheritedAbstractMembers(
            for: interfaceSymbol, symbols: symbols
        ))

        var requirements: [SamRequirementKey: SymbolID] = [:]
        for candidate in candidates {
            guard let member = symbols.symbol(candidate) else { continue }
            guard let key = samRequirementKey(
                for: candidate, interface: interfaceSymbol, symbols: symbols, types: types
            ) else {
                if member.kind == .property { return nil }
                continue
            }
            if coveredKeys.contains(key) { continue }
            if member.kind == .property { return nil }
            if let existing = requirements[key],
               let existingOwner = symbols.parentSymbol(for: existing),
               let newOwner = symbols.parentSymbol(for: candidate),
               !types.isNominalSubtypeSymbol(newOwner, of: existingOwner)
            {
                continue
            }
            requirements[key] = candidate
        }
        let functions = requirements.values
        guard functions.count == 1 else { return nil }
        return functions.first
    }

    private func samRequirementKey(
        for memberID: SymbolID,
        interface: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SamRequirementKey? {
        guard let member = symbols.symbol(memberID),
              let view = abstractMemberViewFromClass(
                  memberID, for: interface, symbols: symbols, types: types
              )
        else { return nil }
        return SamRequirementKey(
            name: member.name,
            kind: member.kind,
            parameterTypes: view.parameterTypes,
            extensionReceiverType: view.extensionReceiverType,
            isSuspend: view.isSuspend
        )
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
              let method = effectiveSamAbstractMethod(for: classType.classSymbol, symbols: sema.symbols, types: sema.types),
              let signature = sema.symbols.functionSignature(for: method)
        else {
            return nil
        }
        var ownerSymbol = classType.classSymbol
        var ownerArgs = classType.args
        if let method = effectiveSamAbstractMethod(for: classType.classSymbol, symbols: sema.symbols, types: sema.types),
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
        var receiverType: TypeID? = includeMemberExtensionReceiver
            && sema.symbols.memberExtensionOwnerSymbol(for: method) != nil
            ? signature.receiverType.map(substitute)
            : nil
        var paramTypes = signature.parameterTypes.map(substitute)
        if receiverType == nil,
           sema.samWithReceiverInterfaces.contains(classType.classSymbol),
           !paramTypes.isEmpty
        {
            receiverType = paramTypes.removeFirst()
        }
        return FunctionType(
            contextReceivers: signature.contextReceiverTypes.map(substitute),
            receiver: receiverType,
            params: paramTypes,
            returnType: substitute(signature.returnType),
            isSuspend: signature.isSuspend,
            nullability: .nonNull
        )
    }
}
