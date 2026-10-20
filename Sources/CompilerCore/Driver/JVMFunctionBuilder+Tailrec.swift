import Foundation

extension JVMFunctionBuilder {
    func prepareTailrec() throws {
        guard declaration.isTailrec, let functionSymbol else { return }
        func visit(_ id: ExprID, result: Bool) {
            TailrecPositionWalker.visit(id, in: arena, isValuePosition: result) { candidate in
                guard program.sema.bindings.callBinding(for: candidate)?.chosenCallee == functionSymbol,
                      let node = arena.expr(candidate) else { return }
                if case .safeMemberCall = node,
                   !program.extensionSymbols.contains(functionSymbol) { return }
                // A call on another instance remains an ordinary virtual call.
                if case let .memberCall(receiver, _, _, _, _) = node,
                   program.methods[functionSymbol] != nil,
                   !program.extensionSymbols.contains(functionSymbol) {
                    guard case .thisRef = arena.expr(receiver) else { return }
                    if let symbol = program.sema.bindings.identifierSymbol(for: receiver),
                       contextualReceivers[symbol]?.slot != thisValue?.slot { return }
                }
                tailrecCalls.insert(candidate)
            }
        }
        switch declaration.body {
        case let .expr(body, _): visit(body, result: true)
        case let .block(body, _):
            for (index, expression) in body.enumerated() {
                visit(expression, result: reference.result == .unit && index == body.count - 1)
            }
        case .unit: break
        }
        guard !tailrecCalls.isEmpty else { return }
        tailrecParameters = try declaration.valueParams.map { try lookup($0.name).value }
        let entry = label()
        tailrecEntry = entry
        mark(entry)
    }

    func emitTailrec(_ id: ExprID, symbol: SymbolID, dispatch: JVMValue?, prefix: [JVMValue], values: [JVMValue], masks: [UInt32]) throws -> Bool {
        guard tailrecCalls.contains(id), symbol == functionSymbol, let entry = tailrecEntry else { return false }
        // Kotlin does not optimize calls that inherit omitted defaults from an
        // overridden declaration; preserve the ordinary default dispatcher.
        if masks.contains(where: { $0 != 0 }),
           let binding = program.sema.bindings.callBinding(for: id),
           program.defaultOwner(binding.defaultArgumentOwner ?? symbol) != symbol { return false }
        // Snapshot every argument before overwriting parameters, including
        // unchanged arguments and receiver changes, so swaps remain simultaneous.
        func snapshot(_ source: JVMValue) throws -> JVMValue {
            let result = try value(source.type)
            instructions.append(.copy(source, result))
            return result
        }
        let inputs = try values.map(snapshot)
        let receiver = try prefix.first.map(snapshot)
        let target = try dispatch.map(snapshot)
        if masks.contains(where: { $0 != 0 }) {
            let savedScopes = scopes, savedExtension = extensionValue, savedContexts = contextualReceivers
            scopes = [[:]]
            extensionValue = receiver ?? extensionValue
            if let functionSymbol, let receiver = extensionValue ?? target ?? thisValue {
                contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: functionSymbol)] = receiver
            }
            defer { scopes = savedScopes; extensionValue = savedExtension; contextualReceivers = savedContexts }
            let maskValues = try masks.map { try constant(.int(Int32(bitPattern: $0)), .int) }
            try program.applyDefaults(self, parameters: declaration.valueParams, inputs: inputs, masks: maskValues)
        }
        if let receiver, let extensionValue { instructions.append(.copy(try convert(receiver, to: extensionValue.type), extensionValue)) }
        if let target, let thisValue { instructions.append(.copy(try convert(target, to: thisValue.type), thisValue)) }
        for (source, parameter) in zip(inputs, tailrecParameters) {
            instructions.append(.copy(try convert(source, to: parameter.type), parameter))
        }
        // Constructor arguments may return before their receiver is initialized.
        // Clear those escaping allocations before the verifier sees a backedge.
        if !pendingAllocations.isEmpty { instructions.append(.abandonAllocations(pendingAllocations)) }
        jump(entry)
        return true
    }
}
