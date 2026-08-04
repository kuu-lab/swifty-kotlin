@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-004: Validates that `StringBuilder.appendLine` overloads resolve
/// through the source-backed stdlib surface.
@Suite
struct StringAppendLineFunctionTests {
    @Test func testAppendLineResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("hello")
            sb.appendLine()

            val result = StringBuilder()
                .appendLine("first")
                .appendLine("second")
                .appendLine()
                .toString()
            println(result)
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])

        let valueOverload = try #require(sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 1
        }, "appendLine(value) overload should be registered")
        #expect(
            sema.symbols.externalLinkName(for: valueOverload) == nil,
            "appendLine(value) should be source-backed"
        )

        let noArgOverload = try #require(sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty
        }, "appendLine() no-arg overload should be registered")
        #expect(
            sema.symbols.externalLinkName(for: noArgOverload) == nil,
            "appendLine() should be source-backed"
        )
    }
}
