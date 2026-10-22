extension JVMFunctionBuilder {
    struct ResolvedCompoundResult {
        let value: JVMValue?
        let mutatesReceiver: Bool
    }

    // Sema already selected either opAssign or the op used by reassignment.
    // Pass the evaluated receiver through calls so getters and captures run once.
    func resolvedCompoundCall(_ op: CompoundAssignOp, receiver: JVMValue, rhs: ExprID, id: ExprID) throws -> ResolvedCompoundResult? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              let symbol = program.sema.symbols.symbol(binding.chosenCallee) else { return nil }
        let names: [CompoundAssignOp: (String, String)] = [
            .plusAssign: ("plusAssign", "plus"), .minusAssign: ("minusAssign", "minus"),
            .timesAssign: ("timesAssign", "times"), .divAssign: ("divAssign", "div"),
            .modAssign: ("remAssign", "rem"),
        ]
        guard let names = names[op] else { return nil }
        let name = context.interner.resolve(symbol.name)
        guard name == names.0 || name == names.1 else { return nil }
        let mutatesReceiver = name == names.0
        let expected: JVMValueType = mutatesReceiver ? .unit : receiver.type
        let args = [CallArgument(expr: rhs)]
        guard let call = try inlineCall(args, receiverValue: receiver, id: id, expectedResult: expected)
            ?? sourceCall(args, receiverValue: receiver, id: id, expectedResult: expected)
            ?? textLibraryCall(args, receiverValue: receiver, id: id, expectedResult: expected) else { return nil }
        if !mutatesReceiver && call.value == nil && !terminated {
            throw fail("Resolved JVM compound operator requires a value.", id)
        }
        return ResolvedCompoundResult(value: call.value, mutatesReceiver: mutatesReceiver)
    }
}
