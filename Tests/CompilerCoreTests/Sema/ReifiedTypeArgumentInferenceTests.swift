#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReifiedTypeArgumentInferenceTests {
    @Test
    func nativeArrayOfIntrinsicRejectsInferredIntersection() throws {
        let source = """
        package kotlin

        interface Marker
        interface Render
        class First : Marker, Render
        class Second : Marker, Render
        fun <T> arrayOf(vararg elements: T): Array<T> = null!!
        fun arrayOfCall() = arrayOf(First(), Second())
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-REIFIED", "Expected a reified arrayOf diagnostic: \(errors)")
        }
    }

    @Test
    func inferredIntersectionIsRejectedOnlyForReifiedArguments() throws {
        let source = """
        package reifiedintersection

        interface Marker
        interface Render
        class First : Marker, Render
        class Second : Marker, Render
        class Box<T> { constructor() }

        inline fun <reified T> arrayOf(vararg elements: T): Box<T> = Box<T>()
        fun reifiedCall() = arrayOf(First(), Second())

        fun <T> listOf(first: T, second: T): T = first
        fun nonReifiedCall() = listOf(First(), Second())
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "Unexpected diagnostics: \(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-REIFIED", "Expected a reified intersection diagnostic: \(errors)")

            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let nonReifiedCall = try #require(ast.arena.exprs.indices.compactMap { index -> CallBinding? in
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      context.sourceManager.path(of: range.start.file) == path,
                      let binding = sema.bindings.callBinding(for: id),
                      let symbol = sema.symbols.symbol(binding.chosenCallee),
                      context.interner.resolve(symbol.name) == "listOf"
                else {
                    return nil
                }
                return binding
            }.first)
            #expect(nonReifiedCall.substitutedTypeArguments.count == 1)
            let inferred = try #require(nonReifiedCall.substitutedTypeArguments.first)
            #expect(isIntersection(inferred, in: sema))
        }
    }

    private func isIntersection(_ type: TypeID, in sema: SemaModule) -> Bool {
        if case .intersection = sema.types.kind(of: type) { return true }
        return false
    }
}
#endif
