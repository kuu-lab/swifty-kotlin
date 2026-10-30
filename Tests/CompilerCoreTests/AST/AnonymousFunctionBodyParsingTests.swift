#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnonymousFunctionBodyParsingTests {
    @Test(arguments: [
        "fun main() { val g = fun(x: Int) = x * 2 }",
        "val f = fun() = 1",
        "val f = named@ fun(): String = \"ok\"",
    ])
    func acceptsPlainExpressionBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "@file:OptIn(kotlin.ExperimentalContextParameters::class)\nval y = context(p: String) fun() = p",
        "val y = fun String.(): String = this",
        "@file:OptIn(kotlin.ExperimentalContextParameters::class)\nval y = context(p: String) fun String.() = p",
    ])
    func acceptsContextReceiverExpressionBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val g = fun(x: Int) { return x * 2 } }",
        "val f = fun() { return 1 }",
    ])
    func acceptsBlockBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }

    // kotlinc reports 'function 'anonymous' must have a body.' for a bodiless
    // `fun(...)` in expression position and still binds the anonymous
    // function value.
    @Test(arguments: [
        "val f = fun(): Int",
        "val f = fun()",
        "val f = fun String.(x: Int): Int",
        "fun main() { val f = fun(): Int }",
        "fun main() { val f = l@ fun(): Int }",
        "fun main() { fun(): Int }",
        "fun foo(x: () -> Int) {}\nfun main() { foo(fun(): Int) }",
        "fun main() { val f = fun(): Int\n    f() }",
        "class C { fun m() { val h = fun(): Int } }",
        "fun main() { val f = fun(): List<Int> }",
        "fun main() { val f = fun(): Int; f() }",
    ])
    func bodilessAnonymousFunctionReportsMustHaveBody(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0426"
                && $0.message == "function 'anonymous' must have a body."
        }, "\(context.diagnostics.diagnostics)")
        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" || $0.code == "KSWIFTK-PARSE-0001"
        }, "\(context.diagnostics.diagnostics)")
    }
}
#endif
