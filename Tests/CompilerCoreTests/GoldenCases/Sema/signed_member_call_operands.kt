package golden.sema

// KUU-3954 positive controls: signed/floating/unsigned/Char receivers keep
// resolving arithmetic members for non-null operands, a safe call unwraps a
// nullable receiver (the operand itself must still be non-null — covered by
// the Diagnostics case), unsigned receivers keep their non-null Nothing
// operand, and equals(Any?) still accepts a nullable argument.

fun main() {
    val x = 5
    val l = 5L
    val d = 1.5
    val f = 1.5f
    val bt: Byte = 1
    val st: Short = 1
    val u: UInt = 1u
    val ul: ULong = 1uL
    val ub: UByte = 1u
    val us: UShort = 1u
    val c = 'a'
    val xn: Int? = 5

    val i1 = x.plus(5)
    val i2 = x.plus(5L)
    val i3 = x.plus(1.5)
    val i4 = x.plus(1.5f)
    val i5 = x.minus(2)
    val i6 = x.times(2)
    val i7 = x.div(2)
    val i8 = x.rem(2)
    val i9 = x.mod(2)
    val i10 = x.floorDiv(2)
    val l1 = l.plus(5)
    val l2 = l.minus(5L)
    val l3 = l.times(5)
    val l4 = l.div(2)
    val l5 = l.rem(2L)
    val l6 = l.mod(2)
    val l7 = l.floorDiv(2L)
    val d1 = d.plus(5)
    val d2 = d.plus(5L)
    val d3 = d.minus(1f)
    val d4 = d.times(2.0)
    val d5 = d.div(2)
    val d6 = d.rem(2.0)
    val f1 = f.plus(5)
    val f2 = f.times(2f)
    val b1 = bt.plus(st)
    val s1 = st.plus(bt)
    val c1 = c.plus(3)
    val c2 = c.minus('b')
    val c3 = c.minus(2)
    val u1 = u.plus(0u)
    val u2 = u.plus(ub)
    val u3 = u.plus(2uL)
    val u4 = u.minus(1u)
    val u5 = u.times(2u)
    val u6 = u.div(2u)
    val u7 = u.rem(2u)
    val u8 = u.mod(2u)
    val u9 = u.floorDiv(2u)
    val u10 = ul.plus(2u)
    val u11 = ub.plus(ub)
    val u12 = us.plus(1u)
    val sh1 = x.shl(1)
    val sh2 = x.shr(1)
    val sh3 = x.ushr(1)
    val bi1 = x.and(3)
    val bi2 = x.or(3)
    val bi3 = x.xor(3)
    val ubi = u.and(3u)
    val sc = xn?.plus(5)
    val eq = x.equals(xn)
    val cmp = x.compareTo(5)
    val nn = u.plus(TODO())
}
