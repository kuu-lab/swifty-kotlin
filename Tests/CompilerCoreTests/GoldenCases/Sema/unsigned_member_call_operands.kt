package golden.sema

// KUU-3936 positive controls: unsigned arithmetic members still resolve for
// unsigned operands, a non-null Nothing argument, and a user-defined operator
// extension taking a signed operand.
operator fun UInt.plus(other: Int): UInt = this + other.toUInt()

fun main() {
    val u: UInt = 1u
    val ul: ULong = 1uL
    val ub: UByte = 1u
    val us: UShort = 1u

    val a = u.plus(0u)
    val b = u.plus(ub)
    val c = u.plus(us)
    val d = u.plus(2uL)
    val e = ul.plus(2u)
    val f = ub.plus(ub)
    val g = us.plus(1u)
    val h = u.minus(1u)
    val i = u.times(2u)
    val j = u.div(2u)
    val k = u.rem(2u)
    val l = u.floorDiv(2u)
    val m = u.mod(2u)
    val n = u.plus(TODO())
    val o = u.plus(5)
}
