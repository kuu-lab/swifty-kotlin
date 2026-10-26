extension TypeSystem {
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
