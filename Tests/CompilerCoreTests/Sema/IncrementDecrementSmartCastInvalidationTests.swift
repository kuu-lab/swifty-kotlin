#if canImport(Testing)
@testable import CompilerCore
import Testing

// KUU-3504: a custom `inc()` call reassigns a mutable local, so a prior
// assignment-based smart cast must not survive the increment expression.
@Suite
struct IncrementDecrementSmartCastInvalidationTests {
    private func context(for source: String) throws -> CompilationContext {
        var result: CompilationContext?
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            result = ctx
        }
        return try requireTestValue(result, "Expected a compilation context after running Sema")
    }

    @Test func postfixIncrementInvalidatesAssignmentNarrowing() throws {
        let ctx = try context(for: """
            interface Base
            class Derived : Base
            class Another : Base
            operator fun Base.inc(): Derived = Derived()

            fun box(): String {
                var i: Base
                i = Another()
                val j = i++
                return if (j is Another && i is Derived) "OK" else "fail"
            }

            fun prefixIncrement(): Boolean {
                var i: Base
                i = Another()
                ++i
                return i is Derived
            }

            fun postfixIncrementDoesNotKeepOperatorResultNarrowing(): Boolean {
                var i: Base
                i = Another()
                i++
                return i is Another
            }
            """)

        let impossibleChecks = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-0415" }
        #expect(impossibleChecks.isEmpty, "Unexpected impossible `is` check after `i++`: \(impossibleChecks)")
    }
}
#endif
