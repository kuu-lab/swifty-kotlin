import Testing

extension BundledStdlibExecutionTests {
    /// KUU-854: a `Long?`/`ULong?`/`Double?`/`Float?` slot holds
    /// box-or-sentinel. A raw scalar bit-equal to the null sentinel
    /// (`Long.MIN_VALUE`, `ULong` 2^63, `-0.0`) must not read as `null` —
    /// every write into a nullable primitive slot boxes a non-null value.
    @Test
    func testNullablePrimitiveSentinelSlotsStayDistinguishableFromNull() throws {
        try compileAndRunKotlin(
            """
            fun returnsMin(): Long? = Long.MIN_VALUE
            fun takesNullable(x: Long?): Boolean = x != null

            fun main() {
                val m: Long? = Long.MIN_VALUE
                println(m)
                println(m != null)

                var v: Long? = 1L
                v = Long.MIN_VALUE
                println(v != null)
                println(v)
                v = null
                println(v != null)

                val d: Double? = -0.0
                println(d != null)
                println(d)
                val f: Float? = -0.0f
                println(f != null)
                val u: ULong? = 9223372036854775808UL
                println(u != null)
                println(u)

                val r = returnsMin()
                println(r != null)
                println(r)
                println(takesNullable(Long.MIN_VALUE))

                val elvis: Long? = (null as Long?) ?: Long.MIN_VALUE
                println(elvis != null)
                println(elvis)

                println(m?.plus(1))
                println(when (m) { null -> "isnull"; else -> "notnull" })

                val sc: Long? = Long.MIN_VALUE
                if (sc != null) { println(sc + 1) }
            }
            """,
            expectedOutput: """
            -9223372036854775808
            true
            true
            -9223372036854775808
            false
            true
            -0.0
            true
            true
            9223372036854775808
            true
            -9223372036854775808
            true
            true
            -9223372036854775808
            -9223372036854775807
            notnull
            -9223372036854775807

            """,
            moduleName: "KUU854LocalSlots"
        )
    }

    /// KUU-854: writes that bypass the local `.copy` path — field offsets,
    /// property initializers, capture cells, custom setter backing fields,
    /// secondary-constructor bodies, and runtime `*OrNull` bridges — must
    /// also leave `P?` slots box-or-sentinel.
    @Test
    func testNullablePrimitiveSentinelSlotsAcrossFieldAndRuntimePaths() throws {
        try compileAndRunKotlin(
            """
            class Holder {
                var field: Long? = 0L
                var initialized: Long? = Long.MIN_VALUE
                var viaSetter: Long? = null
                    set(v) { field = v }
                var secondary: Long? = null
                constructor()
                constructor(v: Long) : this() { secondary = v }
            }

            var captured: Long? = null
            fun capture(): () -> Unit {
                var cell: Long? = 5L
                return { captured = cell; cell = Long.MIN_VALUE }
            }

            fun main() {
                val h = Holder()
                println(h.initialized != null)
                println(h.initialized)
                h.field = Long.MIN_VALUE
                println(h.field != null)
                println(h.field)
                h.viaSetter = Long.MIN_VALUE
                println(h.viaSetter != null)
                println(h.viaSetter)
                val h2 = Holder(Long.MIN_VALUE)
                println(h2.secondary != null)
                println(h2.secondary)

                val lam = capture()
                lam()
                println(captured)

                val anyv: Any = Long.MIN_VALUE
                val cast = anyv as? Long
                println(cast != null)
                println(cast)

                println("-9223372036854775808".toLongOrNull())
                println("-9223372036854775808".toLongOrNull() != null)
                println("abc".toLongOrNull())
                println("9223372036854775808".toULongOrNull() != null)
                println("-0.0".toDoubleOrNull() != null)
                println("-0.0".toFloatOrNull() != null)

                val la = longArrayOf(Long.MIN_VALUE)
                println(la.firstOrNull())
                println(la.firstOrNull() != null)
                println(longArrayOf().firstOrNull())

                val rng = Long.MIN_VALUE..Long.MIN_VALUE
                println(rng.firstOrNull())
                println(rng.lastOrNull())
                println(rng.randomOrNull() != null)

                val arr = arrayOfNulls<Long>(1)
                arr[0] = Long.MIN_VALUE
                println(arr[0])
                println(arr[0] != null)
            }
            """,
            expectedOutput: """
            true
            -9223372036854775808
            true
            -9223372036854775808
            true
            -9223372036854775808
            true
            -9223372036854775808
            5
            true
            -9223372036854775808
            -9223372036854775808
            true
            null
            true
            true
            true
            -9223372036854775808
            true
            null
            -9223372036854775808
            -9223372036854775808
            true
            -9223372036854775808
            true

            """,
            moduleName: "KUU854FieldSlots"
        )
    }

    /// KUU-854 follow-up: with `P?` slots boxed, `==`/`!=` against a
    /// floating-point peer must stay IEEE-754 (`-0.0 == 0.0`, `NaN != NaN`)
    /// once nullness is resolved — for non-null raw peers and nullable
    /// `Double?`/`Float?` peers alike — instead of collapsing to the boxed
    /// `equals` bit-pattern compare.
    @Test
    func testNullablePrimitiveEqualityStaysIEEE() throws {
        try compileAndRunKotlin(
            """
            fun pairEq(a: Double?, b: Double?) = a == b
            fun pairNe(a: Double?, b: Double?) = a != b
            fun mixedEq(a: Double?, b: Double) = a == b
            fun floatPairEq(a: Float?, b: Float?) = a == b

            fun main() {
                println(pairEq(-0.0, 0.0))
                println(pairEq(Double.NaN, Double.NaN))
                println(pairEq(-0.0, -0.0))
                println(pairEq(null, -0.0))
                println(pairEq(-0.0, null))
                println(pairEq(null, null))
                println(pairNe(-0.0, 0.0))
                println(mixedEq(-0.0, 0.0))
                println(mixedEq(Double.NaN, Double.NaN))
                println(floatPairEq(-0.0f, 0.0f))
                println(floatPairEq(Float.NaN, Float.NaN))

                val m: Long? = Long.MIN_VALUE
                val m2: Long? = Long.MIN_VALUE
                println(m == Long.MIN_VALUE)
                println(Long.MIN_VALUE == m)
                println(m == m2)
                println(m != m2)
                val u: ULong? = 9223372036854775808UL
                println(u == 9223372036854775808UL)
            }
            """,
            expectedOutput: """
            true
            false
            true
            false
            false
            true
            false
            true
            false
            true
            false
            true
            true
            true
            false
            true

            """,
            moduleName: "KUU854IEEEEquality"
        )
    }
}
