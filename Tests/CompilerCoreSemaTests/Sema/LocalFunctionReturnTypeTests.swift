@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct LocalFunctionReturnTypeTests {
    @Test(arguments: [
        "fun value(): Int = \"wrong\"",
        "fun value(): Int = false",
        "fun value(): Int = { 1 }",
        "fun value(): Int = null",
        "fun value(): Unit = 1",
        "fun value(): Unit = { 1 }",
        "fun <T> value(): T = 1",
        "suspend fun value(): Int = false",
    ])
    func rejectsMismatchedExplicitReturnType(declaration: String) throws {
        let diagnostics = try check("fun main() { \(declaration)\n}")
        #expect(diagnostics.contains { $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001" }, "\(diagnostics)")
    }

    @Test(arguments: [
        "fun value(): Long = 1",
        "fun value(): Int? = null",
        "fun value() = null",
        "fun empty() {}\nfun value(): Unit = empty()",
        "fun value(): Unit { 1 }",
        "fun <T> value(x: T): T = x",
        "fun value(): Int = return 1",
        "suspend fun value(): Int = 1",
        "fun value(): () -> Int = { 1 }",
    ])
    func preservesCompatibleAndInferredReturnTypes(declaration: String) throws {
        let diagnostics = try check("fun main() { \(declaration)\n}")
        #expect(!diagnostics.contains { $0.severity == .error }, "\(diagnostics)")
    }

    @Test(arguments: [
        ("IntRange", "1..3", false),
        ("LongRange", "1L..3L", false),
        ("CharRange", "'a'..'c'", false),
        ("LongRange", "1..3", true),
    ])
    func rangeReturnRequiresMatchingElementType(type: String, body: String, rejects: Bool) throws {
        // Minimal nominal shells keep this a frontend test; primitive range
        // expressions use the same element-type binding as bundled ranges.
        let diagnostics = try check("""
        package kotlin.ranges
        class IntRange
        class LongRange
        class CharRange
        fun main() {
            fun value(): \(type) = \(body)
        }
        """)
        #expect(diagnostics.contains { $0.severity == .error } == rejects, "\(diagnostics)")
        if rejects {
            #expect(diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" }, "\(diagnostics)")
        }
    }

    private func check(_ source: String) throws -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            diagnostics = context.diagnostics.diagnostics
        }
        return diagnostics
    }
}
