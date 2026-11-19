import Foundation

extension JVMFunctionBuilder {
    /// Lowers the synthetic `kotlin.String.Companion.format` members (see
    /// `registerStringCompanionFormatMembers`) to the JDK's static
    /// `java/lang/String.format`, matching stock Kotlin's inlined result. The
    /// companion receiver is implicit for these members, so `args` holds only
    /// the declared value parameters: the format string followed by the
    /// vararg elements.
    func stringCompanionFormatCall(_ symbolID: SymbolID, receiver: ExprID?, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let symbol = program.sema.symbols.symbol(symbolID),
              context.interner.resolve(symbol.name) == "format",
              args.count >= 1
        else { return nil }
        guard let parent = program.sema.symbols.parentSymbol(for: symbolID),
              let parentSymbol = program.sema.symbols.symbol(parent),
              parentSymbol.fqName.map(context.interner.resolve) == ["kotlin", "String", "Companion"]
        else { return nil }

        // `java/lang/String.format` is static and ignores the companion receiver,
        // but the receiver expression is still evaluated for its side effects.
        if let receiver {
            _ = try expression(receiver, discarded: true)
        }
        let formatValue = try convert(requireValue(args[0].expr), to: .string)
        var varargInputs: [(JVMValue, Bool)] = []
        for argument in args.dropFirst() {
            let value = try requireValue(argument.expr)
            if argument.isSpread {
                // Snapshot a spread array at its evaluation point so a later
                // argument cannot mutate it before the vararg array is packed;
                // stock Kotlin copies spread arguments when they are evaluated.
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
