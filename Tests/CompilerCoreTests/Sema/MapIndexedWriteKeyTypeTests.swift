#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// `map[wrongKey] = v` / `map[wrongKey] += v` must be rejected at compile time
/// instead of falling through to the built-in array fallback and panicking at
/// runtime (KUU-3667). A receiver with no indexed `set` convention at all is
/// rejected the same way.
@Suite
struct MapIndexedWriteKeyTypeTests {
    @Test(arguments: [
        // `get`/`set` candidates exist but reject the mismatched key type.
        "fun probe() { val m = hashMapOf(\"a\" to \"b\"); m[1] = \"c\" }",
        "fun probe() { val m = hashMapOf(\"a\" to \"b\"); m[1] += \"c\" }",
        "fun probe() { val m = mutableMapOf(1 to \"b\"); m[\"k\"] = \"c\" }",
        "fun probe() { val m = HashMap<String, String>(); m[1] = \"B\" }",
        "fun probe() { val m = HashMap<String, String>(); m[1] += \"B\" }",
        // A receiver with no indexed set convention at all must not reach the
        // raw array write path either (kotlinc: no set method providing array
        // access).
        "fun probe() { val p = 1 to \"a\"; p[0] = 2 }",
        "fun probe() { class Box(var v: Int); val b = Box(1); b[0] = 2 }",
        "fun probe() { class Box(var v: Int); val b = Box(1); b[0] += 2 }",
    ])
    func wrongKeyTypeOrMissingSetIsRejected(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    /// All of these writes satisfy the indexed `set` convention's parameter
    /// types — MutableMap.set resolves the map writes, while arrays and
    /// mutable lists keep their member/intrinsic `set` path.
    @Test
    func matchingKeyTypeAndArrayWritesAreAccepted() throws {
        let ctx = makeContextFromSource("""
        fun probe() {
            val m = hashMapOf("a" to "b"); m["a"] = "c"; m["a"] += "d"
            val mm = mutableMapOf("a" to "b"); mm["a"] = "c"
            val a = intArrayOf(1); var i = 0; a[i] = 2; a[0] += 3
            val l = mutableListOf(1); l[0] = 2; l[0] += 3
            val arr = arrayOf(1, 2); arr[1] += 4
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
