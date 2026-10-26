extension TypeSystem {
    /// Returns the ordinary callable signature represented by a regular function
    /// value or by a nominal class that implements a regular FunctionN interface.
    func suspendConversionSourceFunctionType(from source: TypeID, to target: TypeID) -> TypeID? {
        guard case let .functionType(targetFunction) = kind(of: target),
              targetFunction.isSuspend
        else {
            return nil
        }

        let sourceFunction: FunctionType
        switch kind(of: source) {
        case let .functionType(function):
            sourceFunction = function
        case let .classType(classType):
            if let directFunction = nominalFunctionType(for: source), !directFunction.isSuspend {
                sourceFunction = directFunction
            } else {
                let arity = targetFunction.contextReceivers.count
                    + targetFunction.params.count
                    + (targetFunction.receiver == nil ? 0 : 1)
                guard let inheritedFunction = inheritedFunctionInterfaceClassType(
                    of: classType,
                    arity: arity,
                    isSuspend: false
                ),
                      let function = nominalFunctionType(for: make(.classType(inheritedFunction)))
                else {
                    return nil
                }
                sourceFunction = function
            }
        default:
            return nil
        }

        guard !sourceFunction.isSuspend,
              sourceFunction.nullability == .nonNull
        else {
            return nil
        }
        return make(.functionType(sourceFunction))
    }

    /// Suspend conversion is a contextual adaptation, not a subtype relation.
    func suspendConversionType(from source: TypeID, to target: TypeID) -> TypeID? {
        guard let sourceFunctionType = suspendConversionSourceFunctionType(from: source, to: target),
              case let .functionType(sourceFunction) = kind(of: sourceFunctionType),
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
