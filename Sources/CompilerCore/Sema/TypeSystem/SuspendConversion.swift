extension TypeSystem {
    /// Suspend conversion is an argument adaptation, not a subtype relation.
    func suspendConversionType(from source: TypeID, to target: TypeID) -> TypeID? {
        guard case let .functionType(sourceFunction) = kind(of: source),
              !sourceFunction.isSuspend,
              sourceFunction.nullability == .nonNull,
              case let .functionType(targetFunction) = kind(of: target),
              targetFunction.isSuspend
        else {
            return nil
        }
        return make(.functionType(FunctionType(
            contextReceivers: sourceFunction.contextReceivers,
            receiver: sourceFunction.receiver,
            params: sourceFunction.params,
            returnType: sourceFunction.returnType,
            isSuspend: true,
            nullability: sourceFunction.nullability,
            throws: sourceFunction.throws
        )))
    }
}
