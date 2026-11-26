import Foundation

extension JVMFunctionBuilder {
    func resultCompanionCall(_ symbolID: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.count == 1,
              let parent = program.sema.symbols.parentSymbol(for: symbolID),
              (try? program.className(parent)) == "kotlin/Result$Companion",
              let symbol = program.sema.symbols.symbol(symbolID)
        else { return nil }

        let argument = try requireValue(args[0].expr)
        let carrier: JVMValueType = .reference("java/lang/Object", nullable: true)
        let resultType = try program.expressionType(id)
        switch context.interner.resolve(symbol.name) {
        case "success":
            if !context.options.stdlibOnly {
                return JVMIntrinsicResult(value: try convert(argument, to: resultType))
            }
            let value = try convert(argument, to: carrier)
            return JVMIntrinsicResult(value: try jdkCall(
                "kotlin/Result",
                "box-impl",
                [carrier],
                resultType,
                arguments: [value]
            ))
        case "failure":
            if !context.options.stdlibOnly {
                let throwable: JVMValueType = .reference("java/lang/Throwable", nullable: false)
                return JVMIntrinsicResult(value: try jdkCall(
                    "kotlin/ResultKt",
                    "createFailure",
                    [throwable],
                    carrier,
                    arguments: [argument],
                    resolved: resultType
                ))
            }
            let throwable: JVMValueType = .reference("java/lang/Throwable", nullable: false)
            let failure = try jdkCall(
                "kotlin/ResultKt",
                "createFailure",
                [throwable],
                carrier,
                arguments: [argument]
            )!
            return JVMIntrinsicResult(value: try jdkCall(
                "kotlin/Result",
                "box-impl",
                [carrier],
                resultType,
                arguments: [failure]
            ))
        default:
            return nil
        }
    }
}
