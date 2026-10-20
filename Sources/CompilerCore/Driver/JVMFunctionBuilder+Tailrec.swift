import Foundation

extension JVMFunctionBuilder {
    func prepareTailrec() throws {
        guard declaration.isTailrec, let functionSymbol else { return }
        func visit(_ id: ExprID, result: Bool) {
            guard let node = arena.expr(id) else { return }
            switch node {
            case let .returnExpr(value, target, _) where target == nil:
                if let value { visit(value, result: true) }
            case .call, .memberCall:
                if result, program.sema.bindings.callBinding(for: id)?.chosenCallee == functionSymbol {
                    tailrecCalls.insert(id)
                }
            case let .ifExpr(_, yes, no, _):
                visit(yes, result: result)
                if let no { visit(no, result: result) }
            case let .whenExpr(_, branches, fallback, _):
                for branch in branches { visit(branch.body, result: result) }
                if let fallback { visit(fallback, result: result) }
            case let .blockExpr(statements, trailing, _):
                for statement in statements { visit(statement, result: false) }
                if let trailing { visit(trailing, result: result) }
            case let .binary(.elvis, _, rhs, _): visit(rhs, result: result)
            default: break
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
        jump(entry)
        return true
    }
}
