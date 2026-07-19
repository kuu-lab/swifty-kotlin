extension CallLowerer {
    func tryLowerTableDrivenStringMemberCall(
        receiverExpr: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        loweredReceiverID: KIRExprID,
        loweredArgIDs: [KIRExprID],
        normalizedArgIDs: [KIRExprID],
        result: KIRExprID,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        let receiverType = sema.bindings.exprTypes[receiverExpr] ?? sema.types.anyType
        guard let receiverKind = MemberRuntimeDispatch.stringReceiverKind(
            receiverType: receiverType,
            sema: sema,
            interner: interner
        ) else {
            return nil
        }
        let dispatchKey = MemberDispatchKey(
            receiverKind: receiverKind,
            memberName: interner.resolve(calleeName),
            arity: args.count
        )
        guard let runtimeCall = MemberRuntimeDispatch.stringRuntimeCall(for: dispatchKey) else {
            return nil
        }

        let memberArguments = runtimeCall.argumentMode == .normalized ? normalizedArgIDs : loweredArgIDs
        let thrownResult: KIRExprID? = switch runtimeCall.thrownResultMode {
        case .none:
            nil
        case .nullableAny:
            arena.appendTemporary(type: sema.types.nullableAnyType)
        }
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern(runtimeCall.runtimeLinkName),
            arguments: [loweredReceiverID] + memberArguments,
            result: result,
            canThrow: runtimeCall.canThrow,
            thrownResult: thrownResult
        ))
        return result
    }
}
