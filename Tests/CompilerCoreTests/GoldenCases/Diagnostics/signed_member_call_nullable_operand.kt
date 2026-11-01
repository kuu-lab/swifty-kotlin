package golden.diagnostics

// KUU-3954: signed/floating primitive arithmetic members have no
// nullable-operand overloads in Kotlin (`x.plus(xn)` where xn: Int? fails
// in kotlinc with "argument type mismatch"). The primitive fast path used
// to strip operand nullability via makeNonNullable — and for
// Double/Float/Long/unsigned receivers skipped operand checks entirely —
// so these calls bound anyway. Operands that are not numeric primitives at
// all (`d.plus("a")`) used to bind too and only died at link time; they now
// surface as unresolved members like the rest.

fun main() {
    val x = 5
    val l = 5L
    val d = 1.5
    val f = 1.5f
    val b: Byte = 1
    val s: Short = 1
    val u: UInt = 1u
    val ul: ULong = 1uL
    val c = 'a'
    val xn: Int? = 5
    val ln: Long? = 5L
    val dn: Double? = 1.5
    val un: UInt? = 1u

    x.plus(xn)
    x.plus(ln)
    x.plus(dn)
    x.minus(xn)
    x.times(xn)
    x.div(xn)
    x.rem(xn)
    x.mod(xn)
    x.floorDiv(xn)
    1.plus(xn)
    d.plus(xn)
    d.plus(ln)
    d.plus(dn)
    f.plus(xn)
    l.plus(xn)
    l.plus(ln)
    l.minus(ln)
    l.times(ln)
    l.div(ln)
    l.rem(ln)
    l.mod(ln)
    l.floorDiv(ln)
    b.plus(xn)
    s.plus(xn)
    u.plus(un)
    u.mod(un)
    u.floorDiv(un)
    ul.plus(un)
    c.plus(xn)
    c.minus(xn)
    x.plus(null)
    xn?.plus(xn)
    d.plus("a")
    d.plus(true)
    5L.plus("a")

    // Still legal: non-null operands, a safe call with a non-null operand,
    // and equals(Any?) which takes a nullable argument.
    x.plus(5)
    x.plus(5L)
    x.plus(1.5)
    d.plus(5)
    l.plus(5)
    f.plus(5)
    c.plus(3)
    c.minus('b')
    x.mod(5)
    x.floorDiv(5)
    xn?.plus(5)
    u.plus(0u)
    x.equals(xn)
}

fun rejectsNothingOperand() {
    // A non-null Nothing argument is an ambiguous overload for signed and
    // floating receivers in kotlinc, so it must not resolve here either;
    // unsigned receivers do accept it (see acceptsUnsignedNothingOperand).
    val x = 5
    val d = 1.5
    x.plus(TODO())
    d.plus(TODO())
}

fun acceptsUnsignedNothingOperand() {
    val u: UInt = 1u
    u.plus(TODO())
}
