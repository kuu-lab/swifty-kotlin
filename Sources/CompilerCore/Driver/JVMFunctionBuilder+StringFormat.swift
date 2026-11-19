import Foundation

extension JVMFunctionBuilder {
    /// Lowers the synthetic `kotlin.String.Companion.format` members (see
    /// `registerStringCompanionFormatMembers`) to the JDK's static
    /// `java/lang/String.format`, matching stock Kotlin's inlined result. The
    /// companion receiver is implicit for these members, so `args` holds only
    /// the declared value parameters: the format string followed by the
    /// vararg elements.
    func stringCompanionFormatCall(_ symbolID: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard let symbol = program.sema.symbols.symbol(symbolID),
              context.interner.resolve(symbol.name) == "format",
              args.count >= 1,
              args.allSatisfy({ !$0.isSpread })
        else { return nil }
        guard let parent = program.sema.symbols.parentSymbol(for: symbolID),
              let parentSymbol = program.sema.symbols.symbol(parent),
              parentSymbol.fqName.map(context.interner.resolve) == ["kotlin", "String", "Companion"]
        else { return nil }

        let formatValue = try convert(requireValue(args[0].expr), to: .string)
        let varargInputs: [(JVMValue, Bool)] = try args.dropFirst().map { argument in
            (try requireValue(argument.expr), argument.isSpread)
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
