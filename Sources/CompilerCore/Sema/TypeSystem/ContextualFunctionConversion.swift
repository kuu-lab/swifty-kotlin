extension TypeSystem {
    /// Finds a function-type view through intersections, type-parameter bounds,
    /// or a nominal FunctionN supertype when that view can satisfy `target`.
    /// SAM conversion uses this when the value's static type is not itself a
    /// function type.
    func functionTypeWitness(from source: TypeID, compatibleWith target: TypeID) -> TypeID? {
        var visitedParameters: Set<SymbolID> = []

        func find(_ candidate: TypeID) -> TypeID? {
            switch kind(of: candidate) {
            case .functionType:
                let converted = functionArgumentConversionType(from: candidate, to: target) ?? candidate
                return isSubtype(converted, target) ? candidate : nil

            case let .intersection(parts):
                for part in parts {
                    if let witness = find(part) { return witness }
                }
                return nil

            case let .typeParam(parameter):
                if let capture = parameter.capture {
                    return find(withNullability(parameter.nullability, for: capture.upper))
                }
                guard visitedParameters.insert(parameter.symbol).inserted else { return nil }
                for bound in declaredUpperBounds(for: parameter.symbol) {
                    if let witness = find(withNullability(parameter.nullability, for: bound)) {
                        return witness
                    }
                }
                return nil

            case let .classType(classType):
                guard case let .functionType(targetFunction) = kind(of: target) else {
                    return nil
                }
                let arity = targetFunction.contextReceivers.count
                    + (targetFunction.receiver == nil ? 0 : 1)
                    + targetFunction.params.count
                let sourceFunction = nominalFunctionType(for: candidate)
                    ?? inheritedFunctionInterfaceClassType(
                        of: classType,
                        arity: arity,
                        isSuspend: targetFunction.isSuspend
                    ).flatMap { inherited in
                        nominalFunctionType(for: make(.classType(inherited)))
                    }
                guard let sourceFunction else { return nil }
                let sourceFunctionType = make(.functionType(sourceFunction))
                let converted = functionArgumentConversionType(
                    from: sourceFunctionType,
                    to: target
                ) ?? sourceFunctionType
                return isSubtype(converted, target) ? sourceFunctionType : nil

            default:
                return nil
            }
        }

        return find(source)
    }

    /// Reclassifies leading parameters of an ordinary function as context
    /// parameters when an expected context function type supplies that shape.
    func contextualFunctionConversionType(from source: TypeID, to target: TypeID) -> TypeID? {
        guard case let .functionType(sourceFunction) = kind(of: source),
              sourceFunction.contextReceivers.isEmpty,
              sourceFunction.receiver == nil,
              case let .functionType(targetFunction) = kind(of: target),
              !targetFunction.contextReceivers.isEmpty
        else {
            return nil
        }

        let targetReceiverCount = targetFunction.receiver == nil ? 0 : 1
        let targetInputCount = targetFunction.contextReceivers.count
            + targetReceiverCount
            + targetFunction.params.count
        guard sourceFunction.params.count == targetInputCount else {
            return nil
        }

        let contextCount = targetFunction.contextReceivers.count
        let receiver = targetFunction.receiver == nil ? nil : sourceFunction.params[contextCount]
        let paramsStart = contextCount + targetReceiverCount
        return make(.functionType(FunctionType(
            contextReceivers: Array(sourceFunction.params.prefix(contextCount)),
            receiver: receiver,
            params: Array(sourceFunction.params.dropFirst(paramsStart)),
            returnType: sourceFunction.returnType,
            isSuspend: sourceFunction.isSuspend,
            isCallableReference: sourceFunction.isCallableReference,
            nullability: sourceFunction.nullability,
            throws: sourceFunction.throws
        )))
    }

    /// Applies call-site function adaptations while keeping them separate from
    /// ordinary function subtyping.
    func functionArgumentConversionType(from source: TypeID, to target: TypeID) -> TypeID? {
        let suspendConverted = suspendConversionType(from: source, to: target) ?? source
        if let contextualConverted = contextualFunctionConversionType(from: suspendConverted, to: target) {
            return contextualConverted
        }
        return suspendConverted == source ? nil : suspendConverted
    }
}
