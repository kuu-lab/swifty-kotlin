import Foundation

extension JVMFunctionBuilder {
    func stringCompanionFormatCall(_ symbolID: SymbolID, receiver: ExprID?, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let symbol = program.sema.symbols.symbol(symbolID),
              context.interner.resolve(symbol.name) == "format",
              args.count >= 1
        else { return nil }
        guard let parent = program.sema.symbols.parentSymbol(for: symbolID),
              let parentSymbol = program.sema.symbols.symbol(parent),
              parentSymbol.fqName.map(context.interner.resolve) == ["kotlin", "String", "Companion"]
        else { return nil }

        if let receiver {
            _ = try expression(receiver, discarded: true)
        }
        let formatValue = try convert(requireValue(args[0].expr), to: .string)
        var varargInputs: [(JVMValue, Bool)] = []
        for argument in args.dropFirst() {
            let value = try requireValue(argument.expr)
            if argument.isSpread {
                let snapshot = try textVararg([(value, true)], element: .reference("java/lang/Object", nullable: true))
                varargInputs.append((snapshot, true))
            } else {
                varargInputs.append((value, false))
            }
        }
        let objectArray = try textVararg(varargInputs, element: .reference("java/lang/Object", nullable: true))
        let result = try jdkCall(
            "java/lang/String",
            "format",
            [.string, .reference("[Ljava/lang/Object;", nullable: false)],
            .string,
            arguments: [formatValue, objectArray],
            resolved: program.expressionType(id)
        )
        return JVMIntrinsicResult(value: result)
    }
}
