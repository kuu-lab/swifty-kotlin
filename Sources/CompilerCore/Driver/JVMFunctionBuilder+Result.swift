import Foundation

extension JVMFunctionBuilder {
    func resultCompanionCall(_ symbolID: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.count == 1,
              let parent = program.sema.symbols.parentSymbol(for: symbolID),
              (try? program.className(parent)) == "kotlin/Result$Companion",
              let symbol = program.sema.symbols.symbol(symbolID)
        else { return nil }

        let argument = try requireValue(args[0].expr)
        switch context.interner.resolve(symbol.name) {
        case "success":
            return JVMIntrinsicResult(value: try convert(argument, to: program.expressionType(id)))
        case "failure":
            let throwable: JVMValueType = .reference("java/lang/Throwable", nullable: false)
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            return JVMIntrinsicResult(value: try jdkCall(
                "kotlin/ResultKt",
                "createFailure",
                [throwable],
                object,
                arguments: [argument],
                resolved: program.expressionType(id)
            ))
        default:
            return nil
        }
    }
}
