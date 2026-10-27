extension CallTypeChecker {
    /// A projected Channel can only consume its lower element bound.
    func channelSendParameterType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard ReceiverClassifier(sema: sema, interner: interner).isChannelReceiverType(receiverType),
              let element = resolveClassType(receiverType, sema: sema)?.args.first
        else { return nil }
        switch element {
        case let .invariant(type), let .in(type):
            return type
        case .out, .star:
            return sema.types.nothingType
        }
    }

    /// Defer callable arguments that cannot match the intrinsic's element
    /// type so an applicable extension can supply their expected type.
    func channelSendDefersArgument(
        _ argument: CallArgument,
        parameterType: TypeID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let expression = ctx.ast.arena.expr(argument.expr)
        guard expression?.isLambdaOrCallableRef == true else { return false }
        let sema = ctx.sema
        let expected = sema.types.makeNonNullable(parameterType)
        let function: FunctionType?
        if case let .functionType(type) = sema.types.kind(of: expected) {
            function = type
        } else {
            function = sema.types.nominalFunctionType(for: expected)
                ?? driver.helpers.samFunctionType(for: expected, sema: sema)
        }
        if let function {
            guard case let .lambdaLiteral(parameters, _, _, _) = expression else { return false }
            return parameters.isEmpty ? function.params.count > 1 : parameters.count != function.params.count
        }
        switch sema.types.kind(of: expected) {
        case .any, .typeParam, .error:
            return false
        default:
            return true
        }
    }
}
