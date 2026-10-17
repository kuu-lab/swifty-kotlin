extension TypeCheckHelpers {
    func memberPropertyWriteType(
        symbol: SymbolID, receiverType: TypeID, fallback: TypeID, sema: SemaModule
    ) -> TypeID {
        guard let owner = sema.symbols.parentSymbol(for: symbol),
              let declaredType = sema.symbols.propertyType(for: symbol),
              let receiver = propertyReceiverClassType(receiverType, owner: owner, sema: sema)
        else { return fallback }
        let parameters = sema.types.nominalTypeParameterSymbols(for: receiver.classSymbol)
        // Lifting concrete arguments erases their use-site projection. Lift
        // symbolic arguments instead, then approximate the original intervals
        // after substituting the declaring owner's property type.
        let symbolicArguments = parameters.map {
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
        }
        guard let ownerArguments = sema.types.liftedNominalSupertypeArgs(
            from: receiver.classSymbol, childArgs: symbolicArguments, to: owner
        ) else { return fallback }
        let ownerParameters = sema.types.nominalTypeParameterSymbols(for: owner)
        let ownerVariables = sema.types.makeTypeVarBySymbol(ownerParameters)
        var ownerSubstitution: [TypeVarID: TypeID] = [:]
        for (parameter, argument) in zip(ownerParameters, ownerArguments) {
            guard let variable = ownerVariables[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .in(type), let .out(type): ownerSubstitution[variable] = type
            case .star: ownerSubstitution[variable] = sema.types.nullableAnyType
            }
        }
        let symbolicType = sema.types.substituteTypeParameters(
            in: declaredType, substitution: ownerSubstitution, typeVarBySymbol: ownerVariables
        )
        let nominalBounds = sema.types.nominalTypeParameterUpperBounds(for: receiver.classSymbol)
        var bounds: [SymbolID: (lower: TypeID, upper: TypeID)] = [:]
        for (index, pair) in zip(parameters, receiver.args).enumerated() {
            let (parameter, argument) = pair
            let declaredBounds = nominalBounds.flatMap { $0.indices.contains(index) ? $0[index] : nil }
                ?? sema.symbols.typeParameterUpperBounds(for: parameter)
            let upperBound = declaredBounds.isEmpty ? sema.types.nullableAnyType : sema.types.make(.intersection(declaredBounds))
            switch argument {
            case let .invariant(type): bounds[parameter] = (type, type)
            case let .in(type): bounds[parameter] = (type, upperBound)
            case let .out(type): bounds[parameter] = (sema.types.nothingType, type)
            case .star: bounds[parameter] = (sema.types.nothingType, upperBound)
            }
        }
        return approximatePropertyType(symbolicType, lower: true, bounds: bounds, sema: sema)
    }

    private func propertyReceiverClassType(_ type: TypeID, owner: SymbolID, sema: SemaModule) -> ClassType? {
        var pending = [type]
        var visited: Set<TypeID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else { continue }
            switch sema.types.kind(of: sema.types.makeNonNullable(current)) {
            case let .classType(nominal):
                if sema.types.isNominalSubtypeSymbol(nominal.classSymbol, of: owner) { return nominal }
            case let .typeParam(parameter):
                pending.append(contentsOf: sema.symbols.typeParameterUpperBounds(for: parameter.symbol).reversed())
            case let .intersection(parts): pending.append(contentsOf: parts.reversed())
            default: break
            }
        }
        return nil
    }

    private func approximatePropertyType(
        _ type: TypeID, lower: Bool,
        bounds: [SymbolID: (lower: TypeID, upper: TypeID)], sema: SemaModule,
        activeTypes: Set<TypeID> = []
    ) -> TypeID {
        let types = sema.types
        // F-bounded parameters can refer back to themselves through a nominal.
        guard !activeTypes.contains(type) else { return lower ? types.nothingType : types.nullableAnyType }
        let activeTypes = activeTypes.union([type])
        func approximate(_ type: TypeID, lower: Bool) -> TypeID {
            approximatePropertyType(type, lower: lower, bounds: bounds, sema: sema, activeTypes: activeTypes)
        }
        switch types.kind(of: type) {
        case let .typeParam(parameter):
            guard let bound = bounds[parameter.symbol] else { return type }
            let result = lower ? bound.lower : bound.upper
            let resolved = result == type ? result : approximate(result, lower: lower)
            return parameter.nullability == .nonNull ? resolved : types.withNullability(parameter.nullability, for: resolved)
        case let .functionType(function):
            return types.make(.functionType(FunctionType(
                contextReceivers: function.contextReceivers.map { approximate($0, lower: !lower) },
                receiver: function.receiver.map { approximate($0, lower: !lower) },
                params: function.params.map { approximate($0, lower: !lower) },
                returnType: approximate(function.returnType, lower: lower),
                isSuspend: function.isSuspend, isCallableReference: function.isCallableReference,
                nullability: function.nullability, throws: function.throws
            )))
        case let .classType(nominal):
            let variances = types.nominalTypeParameterVariances(for: nominal.classSymbol)
            var arguments: [TypeArg] = []
            for (index, argument) in nominal.args.enumerated() {
                let declaredVariance = index < variances.count ? variances[index] : .invariant
                switch argument {
                case .star: arguments.append(.star)
                case let .out(inner): arguments.append(.out(approximate(inner, lower: lower)))
                case let .in(inner): arguments.append(.in(approximate(inner, lower: !lower)))
                case let .invariant(inner):
                    switch declaredVariance {
                    case .out: arguments.append(.invariant(approximate(inner, lower: lower)))
                    case .in: arguments.append(.invariant(approximate(inner, lower: !lower)))
                    case .invariant:
                        let low = approximate(inner, lower: true)
                        let high = approximate(inner, lower: false)
                        // No concrete invariant argument represents an unknown
                        // projected type. Only Nothing can be assigned here.
                        if low != high {
                            if lower { return types.withNullability(nominal.nullability, for: types.nothingType) }
                            arguments.append(low == types.nothingType || low == types.nullableNothingType ? .out(high) : .in(low))
                        } else {
                            arguments.append(.invariant(low))
                        }
                    }
                }
            }
            return types.make(.classType(ClassType(
                classSymbol: nominal.classSymbol,
                args: arguments,
                enclosingTypeArgs: nominal.enclosingTypeArgs,
                nullability: nominal.nullability
            )))
        case let .intersection(parts):
            return types.make(.intersection(parts.map { approximate($0, lower: lower) }))
        case let .kClassType(kClass):
            // The compact KClass representation still denotes invariant
            // KClass<T>; a captured argument has no concrete lower instance.
            let low = approximate(kClass.argument, lower: true)
            let high = approximate(kClass.argument, lower: false)
            if low != high {
                if lower { return types.withNullability(kClass.nullability, for: types.nothingType) }
                if let symbol = types.kClassInterfaceSymbol {
                    return types.make(.classType(ClassType(
                        classSymbol: symbol, args: [low == types.nothingType || low == types.nullableNothingType ? .out(high) : .in(low)],
                        nullability: kClass.nullability
                    )))
                }
                return types.nullableAnyType
            }
            return types.makeKClassType(
                argument: low, nullability: kClass.nullability
            )
        default:
            return type
        }
    }
}
