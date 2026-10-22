#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression tests for an empty type annotation after `:` (e.g. `val x: = 1`).
/// kotlinc rejects these; previously the empty token list silently collapsed to
/// "no explicit type" and the malformed source was accepted.
@Suite struct EmptyTypeAnnotationTests {

    /// Frontend without the bundled stdlib: these tests only need Lex through
    /// BuildAST diagnostics, so unresolved stdlib names are never reached.
    private static func frontendContext(from source: String) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [
        "val x: = 1",
        "fun f(a: = 1) {}",
        "fun f(): = 1",
        "fun main() { val y: = 2 }",
        "val x: by lazy { 1 }",
        "fun main() { try {} catch (e: ) {} }",
        "fun <T: > f() {}",
        "class C :",
        "fun main() { for (x: in listOf(1)) {} }",
        "var p: Int = 0\n    set(v:) {}",
        "val q: Int\n    get(): = 1",
        "val q: Int get(): = 1",
        "fun main() { val f = { x: -> x } }",
        "fun <T> f() where T: {}",
    ])
    func emptyTypeAnnotationIsRejected(source: String) throws {
        let ctx = Self.frontendContext(from: source)
        try runFrontend(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0020" && $0.severity == .error
        })
    }

    @Test(arguments: [
        "val value: Int? = null",
        "fun f(value: Int?) {}",
        "fun f(): Int = 1",
        "val x: Int by lazy { 1 }",
        "val x: Int\n    get() = 1",
        "val x: Int\n    get(): Int = 1",
        "var p: Int = 0\n    get() = field\n    set(v: Int) { field = v }",
        "fun main() { val f = { x: Int -> x }; f(1) }",
        "fun main() { for (x: Int in listOf(1)) {} }",
        "fun main() { try {} catch (e: Exception) {} }",
        "fun <T: Comparable<T>> f() {}",
        "fun <T> f() where T: Comparable<T> {}",
    ])
    func validTypeAnnotationIsAccepted(source: String) throws {
        let ctx = Self.frontendContext(from: source)
        try runFrontend(ctx)

        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0020" })
        #expect(!ctx.diagnostics.hasError)
    }
}
#endif
