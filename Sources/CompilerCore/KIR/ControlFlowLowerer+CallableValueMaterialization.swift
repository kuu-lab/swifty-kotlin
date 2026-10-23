extension ControlFlowLowerer {
    /// Materializes statically-known callable values before they flow through
    /// a control-flow merge, where one direct-call target can no longer stand
    /// for every branch.
    func materializeConditionalCallableValue(
        sourceExprID: ExprID,
        value: KIRExprID,
        expectedType: TypeID?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        guard let expectedType,
              driver.ctx.callableValueInfo(for: value) != nil
        else {
            return value
        }

        let normalizedType = sema.types.makeNonNullable(expectedType)
        let functionType: FunctionType
        if case let .functionType(function) = sema.types.kind(of: normalizedType) {
            functionType = function
        } else if let nominalFunctionType = sema.types.nominalFunctionType(for: normalizedType) {
            functionType = nominalFunctionType
        } else {
            return value
        }

        return driver.callLowerer.materializeFunctionValueArgument(
            loweredArgID: value,
            argExprID: sourceExprID,
            functionType: functionType,
            sema: sema,
            arena: arena,
            interner: interner,
            instructions: &instructions
        )
    }
}
