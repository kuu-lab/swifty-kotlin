#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4101: an inferred member property declared in a later declaration
/// (`val size get() = data.size` on a class, `val isZero get() = signum == 0`
/// on an interface) must publish its type before earlier bodies read it —
/// otherwise `x.size` sees the `Any?` placeholder, downstream expressions
/// degrade to the error type, and the member read falls back to a same-named
/// bundled function, reporting `KSWIFTK-SEMA-0309` ("function invocation
/// expected") on a plain property access (kbignum's `CommonBigInt`).
@Suite
struct InferredMemberPropertyForwardReferenceTests {
    @Test
    func laterClassGetterPropertyReadsFromEarlierBody() throws {
        // `P3.size` derives from the intrinsic array member `IntArray.size`,
        // which member lookup cannot see — the precheck must fall back to the
        // statically known result type.
        let ctx = makeContextFromSource("""
        class C3 private constructor(val data: P3, override val signum: Int, var dummy: Boolean) : Iface, Ctor3 by C3 {
            companion object : Ctor3 {
                operator fun invoke(data: P3, signum: Int): C3 = C3(data, signum, false)
                override fun create(v: Int): C3 = C3(P3(1), 1, false)
            }
            override fun inv(): C3 {
                val out = P3(this.data.size)
                val s = out.size
                return C3(out, s, false)
            }
        }

        class P3 internal constructor(val data: IntArray) {
            val size get() = data.size
            constructor(size: Int) : this(IntArray(if (size > 1) size else 1))
        }

        interface Iface { val signum: Int; fun inv(): Iface }
        interface Ctor3 { fun create(v: Int): Iface }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func laterClassGetterPropertyInsideAlsoLambda() throws {
        // The reported shape: `P3(this.data.size).also { ... it.size ... }`
        // on an error receiver used to bind the bundled `size()` function.
        let ctx = makeContextFromSource("""
        class C3(val data: P3) {
            fun inv(): C3 = C3(
                P3(this.data.size).also {
                    for (n in 0 until it.size) it[n] = this.data[n]
                }
            )
        }

        class P3 internal constructor(val data: IntArray) {
            val size get() = data.size
            constructor(size: Int) : this(IntArray(if (size > 1) size else 1))
            operator fun get(index: Int): Int = data[index]
            operator fun set(index: Int, value: Int) { data[index] = value }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func interfaceGetterPropertyReadsFromEarlierBody() throws {
        // Interfaces went through no member-property precheck at all, so an
        // inferred interface getter stayed `Any?` for every forward read.
        let ctx = makeContextFromSource("""
        class C3(val data: P3) {
            fun inv(): Boolean = if (data.isZero) data.isNegative else !data.isPositive
        }

        class P3(override val signum: Int) : Iface

        interface Iface {
            val signum: Int
            val isZero get() = signum == 0
            val isNegative get() = signum < 0
            val isPositive get() = signum > 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func unresolvedGetterBodyStaysOnNormalPass() throws {
        // The intrinsic array fallback must not invent a type for a body that
        // genuinely does not resolve — `size` here has no receiver and no
        // declaration, so the authoritative pass still reports the error.
        let ctx = makeContextFromSource("""
        class A { val x get() = size }
        class B { val size: Int = 7 }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
