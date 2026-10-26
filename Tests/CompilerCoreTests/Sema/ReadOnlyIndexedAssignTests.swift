#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// `list[0] = v`, `map[k] = v` and `str[0] = c` must be rejected at compile
/// time (no `set` operator) instead of reaching the built-in array fallback
/// and panicking at runtime (KUU-2977).
@Suite
struct ReadOnlyIndexedAssignTests {
    @Test(arguments: [
        "fun probe() { val l = listOf(1); l[0] = 2 }",
        "fun probe() { val m = mapOf(1 to 2); m[1] = 3 }",
        "fun probe() { val s = \"ab\"; s[0] = 'x' }",
    ])
    func readOnlyReceiverIsRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        "fun probe() { val a = intArrayOf(1); a[0] = 2 }",
        "fun probe() { val l = mutableListOf(1); l[0] = 2 }",
        "fun probe() { val m = mutableMapOf(1 to 2); m[1] = 3 }",
    ])
    func mutableReceiverIsAccepted(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }
}
#endif
