import Testing

extension BundledStdlibExecutionTests {
    /// KUU-3899: `x!!`/`.nullAssert` on a statically non-null operand whose
    /// runtime slot cannot encode a null value — a raw primitive, or the flat
    /// payload of a value class kept unboxed — must not probe the raw slot
    /// with `kk_op_notnull`. The null-sentinel bit pattern is a legitimate
    /// value there (`Long.MIN_VALUE`, `ULong` 2^63, `-0.0`, or `V(null)` for
    /// a nullable underlying type), never a null reference, so the probe can
    /// only fire spuriously. Nullable `V?`/primitive slots keep the probe on
    /// the nominal box/handle, which still throws NPE on a real null.
    ///
    /// JVM's `checkNotNull` throws on `v!!` for a *direct* flat `Int?`
    /// payload of `V(null)` — a carrier artifact (it cannot distinguish a
    /// null payload from a null object). KSwiftK deliberately treats `!!` on
    /// a statically non-null operand as a no-op instead (the ticket's "误
    /// throw"), so a few lines below intentionally diverge from JVM output.
    @Test
    func testNullAssertOnUnboxedNonNullOperandDoesNotProbePayload() throws {
        try compileAndRunKotlin(
            """
            @JvmInline
            value class IC(val s: Int?)

            @JvmInline
            value class VL(val s: Long)

            fun mkIC(): IC = IC(null)
            fun mkVL(): VL = VL(Long.MIN_VALUE)

            fun main() {
                // A non-null `V` slot's flat payload may legitimately hold the
                // sentinel bit pattern — `V(null)` here — and `!!` must not
                // throw on it. (JVM's checkNotNull NPEs on this direct flat
                // payload; the ticket declares that throw a bug, so KSwiftK
                // intentionally diverges.)
                val ic: IC = mkIC()
                println(ic!!.s == null)
                println(mkIC()!!.s == null)

                // A flat Long payload can itself collide with the sentinel
                // bit pattern (Int64.min) — `VL(Long.MIN_VALUE)!!` is a valid
                // non-null value on JVM and must not throw.
                val vl: VL = mkVL()
                println(vl!!.s == Long.MIN_VALUE)
                println(mkVL()!!.s)

                // Raw non-null primitives are unboxed too: `Long.MIN_VALUE!!`
                // is a legitimate Long, not null.
                val l: Long = Long.MIN_VALUE
                println(l!! == Long.MIN_VALUE)
                val u: ULong = 9223372036854775808UL
                println(u!! == 9223372036854775808UL)
                val d: Double = -0.0
                println(d!! == -0.0)

                // The `V?` slot still checks the nominal box: a non-null box
                // wrapping a null payload passes, a real null throws NPE.
                val n: IC? = IC(null)
                println(n!!.s == null)
                val z: IC? = null
                try {
                    z!!
                    println("z nothrow")
                } catch (e: NullPointerException) {
                    println("z npe")
                }

                // An unboxed value class delivered through a nullable box is
                // unwrapped before use; `!!` on the box is the same probe as
                // any nullable slot.
                fun takeNullable(v: IC?): IC = v!!
                println(takeNullable(IC(null)).s == null)
            }
            """,
            expectedOutput: """
            true
            true
            true
            -9223372036854775808
            true
            true
            true
            true
            z npe
            true

            """
        )
    }

    /// KUU-3899 regression for the upstream case
    /// `coroutines/inlineClasses/resume/covariantOverrideSuspendFunWithNullableInlineClass_NullableInt_null`:
    /// a non-null `IC` returned from a suspend function is delivered through
    /// the boxed `IC?`/generic ABI; `!!` must check the nominal box, not the
    /// unboxed nullable payload sentinel, and must not throw on `IC(null)`.
    @Test
    func testNullAssertOnSuspendDeliveredValueClassChecksBox() throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            @JvmInline
            value class IC(val s: Int?)

            var c: Continuation<Any>? = null

            suspend fun <T> suspendMe(): T = suspendCoroutine {
                @Suppress("UNCHECKED_CAST")
                c = it as Continuation<Any>
            }

            interface IBar {
                suspend fun bar(): IC?
            }

            fun Int?.toResultString() =
                if (this == null) "OK" else "!!! ${'$'}this"

            class Test : IBar {
                override suspend fun bar(): IC = suspendMe()

                suspend fun test1(): String {
                    val b: IBar = this
                    return b.bar()!!.s.toResultString()
                }

                suspend fun test2(): String {
                    return bar()!!.s.toResultString()
                }
            }

            fun builder(f: suspend () -> Unit) {
                f.startCoroutine(object : Continuation<Unit> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Unit>) {
                        result.getOrThrow()
                    }
                })
            }

            fun main() {
                var result = "FAIL"
                builder { result = Test().test1() }
                c?.resume(IC(null))
                println(result)

                result = "FAIL2"
                builder { result = Test().test2() }
                c?.resume(IC(null))
                println(result)
            }
            """,
            expectedOutput: """
            OK
            OK

            """
        )
    }
}
