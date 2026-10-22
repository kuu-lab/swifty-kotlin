#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-2785: a `(` or `{` left open at the `}` / EOF that ends its enclosing
/// statement, lambda or block must be reported, not completed implicitly.
@Suite
struct UnclosedDelimiterParsingTests {
    @Test(arguments: [
        "fun <T, V, R> compose(f: (V) -> R, g: (T) -> V): (T) -> R = { f(g(it) }",
        "fun f(x: Int) = x\nfun main() { println(f(21 }",
        "fun f(x: Int) = x\nfun main() {\n    val y = f(21\n}",
        "fun main() { val b = { println(1 }\n}",
        "fun main() { println(\"a\".trim( }",
        "fun main() { println(listOf<Int>( }",
    ])
    func reportsUnclosedCallParenthesis(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" && $0.severity == .error
        })
    }

    @Test(arguments: [
        "fun main() {\n    if (true) { println(\"a\")\n}",
        "fun main() {",
        "class C {\n    fun f() {}\n",
        "enum class E {\n    A, B;\n",
        "fun main() { run { println(1) }",
    ])
    func reportsUnclosedBlockAtEndOfFile(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0026" && $0.severity == .error
        })
    }

    @Test(arguments: [
        "fun f(x: Int) = x\nfun main() { println(f(21)) }",
        "fun main() {\n    if (true) { println(\"a\") }\n}",
        "fun main() { val b = { println(1) }\n    b() }",
        "class C {\n    fun f() {}\n}\nfun main() { C().f() }",
        "enum class E { A, B; }\nfun main() { println(E.A) }",
        "fun main() { run { println(1) } }",
    ])
    func acceptsBalancedDelimiters(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" || $0.code == "KSWIFTK-PARSE-0026"
        })
    }
}
#endif
