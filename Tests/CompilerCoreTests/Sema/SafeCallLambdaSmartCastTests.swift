#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SafeCallLambdaSmartCastTests {
    // `recv?.call { ... }` evaluates its arguments only when the receiver is
    // non-null, so a stable receiver reference narrows while the arguments are
    // checked (`x?.let { x.length }`). The narrowing is scoped to the call.
    @Test(arguments: [
        "name?.let { name.length }",
        "name?.also { name.length }",
        "name?.let { run { name.length } }",
        "name?.let { m[name] }",
        "name?.let { i -> m[name]; i.length }"
    ])
    func narrowsNullableValueParameterInsideArguments(body: String) throws {
        let ctx = makeContextFromSource("""
        fun test(name: String?, m: Map<String, Int>) {
            \(body)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsNullableLocalValInsideArguments() throws {
        let ctx = makeContextFromSource("""
        fun test(flag: Boolean) {
            val name: String? = if (flag) "yes" else null
            name?.let { name.length }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsMemberPropertyInsideArguments() throws {
        let ctx = makeContextFromSource("""
        class Holder(val name: String?) {
            fun test() {
                name?.let { name.length }
                name?.let { this.name.length }
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsMemberPropertyChainInsideArguments() throws {
        let ctx = makeContextFromSource("""
        class Inner(val x: String?)
        class Outer(val inner: Inner)
        fun test(outer: Outer) {
            outer.inner.x?.let { outer.inner.x.length }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsForNonInlineCalleeArguments() throws {
        let ctx = makeContextFromSource("""
        class Box(val v: String) { fun apply2(block: (String) -> Int): Int = block(v) }
        fun test(box: Box?) {
            box?.apply2 { box.v.length }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsCapturedWriteVarWhenWritesPreserveType() throws {
        let ctx = makeContextFromSource("""
        fun test() {
            var name: String? = "x"
            val write = { name = "y" }
            name?.let { name.length }
            write()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func narrowsVarReassignedAfterCall() throws {
        let ctx = makeContextFromSource("""
        fun test() {
            var name: String? = "x"
            name?.let { name.length }
            name = null
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        // Mutable member properties are never stable.
        """
        class Holder(var name: String?) {
            fun test() { name?.let { name.length } }
        }
        """,
        // A custom getter can observe different values between reads.
        """
        class Holder { val name: String? get() = "x"
            fun test() { name?.let { name.length } } }
        """,
        // An open property can be overridden with a mutable getter.
        """
        open class Holder { open val name: String? = "x"
            fun test() { name?.let { name.length } } }
        """,
        // The narrowing is scoped to the call: the receiver may still be
        // null afterwards.
        """
        fun test(name: String?) {
            name?.let { name.length }
            name.length
        }
        """,
        // A write inside the same argument invalidates the narrowing.
        """
        fun test() {
            var name: String? = "x"
            name?.let { name = null; name.length }
        }
        """,
        // A deferred write that can restore null makes the var unstable.
        """
        fun test() {
            var name: String? = "x"
            val write = { name = null }
            name?.let { name.length }
        }
        """,
        // Same through a local function.
        """
        fun test() {
            var name: String? = "x"
            fun write() { name = null }
            name?.let { name.length }
        }
        """
    ])
    func rejectsUnstableOrEscapedNarrowing(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0026", in: ctx)
    }
}
#endif
