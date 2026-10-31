// KUU-3771: an erased-ABI property read (`val i: T`) on a generic value class
// must claim the unboxed payload, not re-tag the payload as the value class —
// the KUU-3670 claim checkcast (kk_op_cast against the erased bound) then
// observes the payload and `IC<T:Int>(42).i` returns 42 instead of throwing
// a spurious ClassCastException (KUU-3409 recurrence).

@JvmInline
value class IC<T: Int>(val i: T)

fun <T: IC<Int>> take(t: T) = t.i

fun main() {
    val ic = IC(42)
    println(ic.i)
    println(IC(7).i)
    val j: Int = ic.i + 1
    println(j)

    // The same claim checkcast applies through the erased-ABI edges that can
    // leave the tagged primitive box in a nominally non-null value-class slot.
    val icn: IC<Int>? = IC(9)
    println(icn?.i)
    println(icn!!.i)
    val icNull: IC<Int>? = null
    println(icNull?.i)
    val a: Any = IC(42)
    println((a as IC<Int>).i)
    println(take(IC(11)))
}
