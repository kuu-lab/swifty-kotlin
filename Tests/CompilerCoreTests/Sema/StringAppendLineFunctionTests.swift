@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-004: Validates that `StringBuilder.appendLine` overloads resolve
/// through the source-backed stdlib surface.
@Suite
struct StringAppendLineFunctionTests {

    // MARK: - appendLine(value) overload

    @Test func testAppendLineWithValueResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("hello")
            sb.appendLine("world")
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected appendLine(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine() no-arg overload

    @Test func testAppendLineNoArgResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
            println(sb.toString())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected appendLine() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - appendLine returns StringBuilder (chaining)

    @Test func testAppendLineChainingResolvesWithoutErrors() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val result = StringBuilder()
                .appendLine("first")
                .appendLine("second")
                .appendLine()
                .toString()
            println(result)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected chained appendLine calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Source member registration

    @Test func testAppendLineWithValueResolvesAsSourceMember() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine("test")
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let valueOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.count == 1
        }
        #expect(valueOverload != nil, "appendLine(value) overload should be registered")
        if let sym = valueOverload {
            #expect(
                sema.symbols.externalLinkName(for: sym) == nil,
                "appendLine(value) should be source-backed"
            )
        }
    }

    @Test func testAppendLineNoArgResolvesAsSourceMember() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val sb = StringBuilder()
            sb.appendLine()
        }
        """)
        try runSema(ctx)
        let interner = ctx.interner
        let sema = ctx.sema!
        let sbSymbols = sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("StringBuilder"),
            interner.intern("appendLine"),
        ])
        let noArgOverload = sbSymbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.parameterTypes.isEmpty
        }
        #expect(noArgOverload != nil, "appendLine() no-arg overload should be registered")
        if let sym = noArgOverload {
            #expect(
                sema.symbols.externalLinkName(for: sym) == nil,
                "appendLine() should be source-backed"
            )
        }
    }
}
