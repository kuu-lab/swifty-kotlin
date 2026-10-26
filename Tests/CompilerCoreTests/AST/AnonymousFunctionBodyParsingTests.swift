#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct AnonymousFunctionBodyParsingTests {
    @Test(arguments: [
        "fun main() { val g = fun(x: Int) = x * 2 }",
        "val f = fun() = 1",
        "@file:OptIn(kotlin.ExperimentalContextParameters::class)\nval y = context(p: String) fun String.() = p",
    ])
    func rejectsExpressionBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0001"
                && $0.message == "Expected '{' for anonymous function body."
        }, "\(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun main() { val g = fun(x: Int) { return x * 2 } }",
        "val f = fun() { return 1 }",
    ])
    func acceptsBlockBodies(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
    }
}
#endif
