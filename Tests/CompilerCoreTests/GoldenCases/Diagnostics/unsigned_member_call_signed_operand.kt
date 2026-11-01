package golden.diagnostics

// KUU-3936: unsigned arithmetic members take only unsigned operands in real
// Kotlin (UInt.plus(UByte/UShort/UInt/ULong) etc.). Signed, floating-point,
// or nullable operands must be rejected; the primitive fast path used to bind
// them anyway, so this locks in the rejection for each operator and receiver.

fun main() {
    val u: UInt = 1u
    val ul: ULong = 1uL
    val ub: UByte = 1u
    val us: UShort = 1u
    val x = 5
    val l = 5L
    val d = 1.5
    val f = 1.5f
    val b: Byte = 1
    val s: Short = 1
    val un: UInt? = 1u

    u.plus(0)
    u.plus(x)
    u.plus(l)
    u.plus(d)
    u.plus(f)
    u.plus(b)
    u.plus(s)
    u.plus(un)
    u.minus(x)
    u.times(x)
    u.div(x)
    u.rem(x)
    u.floorDiv(x)
    u.mod(x)
    u.floorDiv(un)
    u.mod(un)
    ul.plus(x)
    ub.plus(x)
    us.plus(x)
    x.plus(1u)
    x.plus(1uL)
    d.plus(1u)
    u.compareTo(0)

    // Still legal: unsigned operands and non-null Nothing.
    u.plus(0u)
    u.plus(ub)
    u.plus(2uL)
    u.plus(TODO())
}
