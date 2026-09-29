// KUU-854: a nullable Long?/ULong?/Double?/Float? slot must stay
// box-or-sentinel — a raw scalar bit-equal to the null sentinel
// (Long.MIN_VALUE, ULong 2^63, -0.0) must not read as `null`.
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

fun returnsMin(): Long? = Long.MIN_VALUE
fun takesNullable(x: Long?): Boolean = x != null
fun bdEqParam(d: Double?): Boolean = d == 0.0

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

    val r = returnsMin()
    println(r != null)
    println(r)
    println(takesNullable(Long.MIN_VALUE))

    val elvis: Long? = (null as Long?) ?: Long.MIN_VALUE
    println(elvis != null)
    println(elvis)

    println(m?.plus(1))
    println(when (m) { null -> "isnull"; else -> "notnull" })

    val anyv: Any = Long.MIN_VALUE
    val cast = anyv as? Long
    println(cast != null)
    println(cast)

    val sc: Long? = Long.MIN_VALUE
    if (sc != null) { println(sc + 1) }

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

    val j: Long? = if (true) Long.MIN_VALUE else 0L
    println(j)
    println(j != null)

    // `P? == P` with a non-null floating-point peer is IEEE-754 once null is
    // ruled out (-0.0 == 0.0, NaN != NaN); `P? == P?` is boxed `equals`
    // (bit pattern: -0.0 != 0.0, NaN == NaN). The nullable side may now be a
    // tagged box, so the runtime compare must not collapse to pointer bits.
    val bdNeg: Double? = -0.0
    println(bdNeg == 0.0)
    println(bdNeg == -0.0)
    println(bdNeg != 0.0)
    println(0.0 == bdNeg)
    val bdPos: Double? = 0.0
    println(bdNeg == bdPos)
    println(bdNeg != bdPos)
    val bn: Double? = Double.NaN
    println(bn == Double.NaN)
    println(bn != Double.NaN)
    println(bn == bn)
    println(bdEqParam(-0.0))
    println(bdEqParam(0.0))
    println(bdEqParam(null))
    val bfNeg: Float? = -0.0f
    println(bfNeg == 0.0f)
    println(bfNeg == -0.0f)
    println(bfNeg != 0.0f)
    val bfPos: Float? = 0.0f
    println(bfNeg == bfPos)
    println(m == Long.MIN_VALUE)
    println(Long.MIN_VALUE == m)
    println(m != Long.MIN_VALUE)
    val m2: Long? = Long.MIN_VALUE
    println(m == m2)
    println(u == 9223372036854775808UL)
}
