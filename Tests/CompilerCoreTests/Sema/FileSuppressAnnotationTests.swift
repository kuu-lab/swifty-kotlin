#if canImport(Testing)
@testable import CompilerCore
import Testing

// Found while investigating a `@file:Suppress("DEPRECATION_ERROR")` header
// that failed to suppress a deprecation diagnostic raised inside a trailing
// `fun main() { ... }` block body (PR #6562's KSP-1216 native concurrent
// top-level tests). File-level `@Suppress` registers the CST root node's
// range as its suppression window, and that range is the accumulation of
// every top-level declaration's range — see
// `DeclarationBoundaryTests.testRootRangeReachesTrailingBlockBodiedFunction`
// for the parser-level root cause and fix.
@Suite
struct FileSuppressAnnotationTests {
    @Test
    func fileSuppressReachesDiagnosticInsideTrailingBlockBodiedFunction() throws {
        let source = """
        @file:Suppress("DEPRECATION_ERROR")

        @Deprecated("old", level = DeprecationLevel.ERROR)
        fun oldFn(): Int = 1

        fun main() {
            println(oldFn())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path])
            try runSema(context)
            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected errors: \(errors.map { $0.code + ": " + $0.message })")
        }
    }
}
#endif
