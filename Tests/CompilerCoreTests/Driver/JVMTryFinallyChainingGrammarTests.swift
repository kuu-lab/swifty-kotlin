#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite struct JVMTryFinallyChainingGrammarTests {
    @Test(arguments: [
        "fun main() { try { work() } finally { cleanup() }.also { save(it) } }",
        "fun main() { try { work() } catch (e: Exception) { 0 }.also { save(it) } }",
        "fun main() { try { work() } catch (e: Exception) { 0 } finally { cleanup() }.let { it * 2 } }",
        "fun main() { val saved = try { work() } finally { cleanup() }.also { it } }",
        "fun main() { try { work() } finally { cleanup() } }",
        "fun main() { try { work() } catch (e: Exception) { recovery() } finally { cleanup() } }",
        "fun main() { println(try { 1 } finally { 2 } + 3) }",
    ])
    func acceptsTryExpressionsWithPostfixChaining(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { try { work() } }",
        "fun main() { try { work() } catch { 0 } }",
        "fun main() { try { work() } finally { } garbage }",
    ])
    func rejectsInvalidTryExpressions(source: String) throws {
        let context = makeContextFromSource(source, emit: .jvmJar)
        try LexPhase().run(context)
        try JVMSourceValidationPhase().run(context)
        #expect(context.diagnostics.hasError)
    }
}
#endif
