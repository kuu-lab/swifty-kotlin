// KSWIFTK-BUG: `x[i]` bracket notation against an `operator fun get/set`
// whose index parameter is a non-Int integer primitive (Long here) must
// contextualize the bare integer literal index to that parameter type,
// the same way Kotlin already contextualizes it for the assigned value in
// `x[i] = value`. Before the fix, the literal defaulted to Int, overload
// resolution rejected the only get()/set() candidate (Int is not a subtype
// of Long), and both Sema and KIR lowering silently fell back to treating
// the receiver as a raw built-in array, producing garbage values and an
// eventual out-of-bounds crash.
class LongIndexedBox {
    private var data: ByteArray = byteArrayOf(9, 8, 7, 6)

    operator fun get(position: Long): Byte = data[position.toInt()]

    operator fun set(position: Long, value: Byte) {
        data[position.toInt()] = value
    }
}

fun main() {
    val b = LongIndexedBox()
    println(b[0])
    println(b[1])
    println(b[2])
    println(b[3])

    b[0] = 42
    b[1] = 43
    println(b[0])
    println(b[1])

    // Explicit method-call form (the previously-working workaround) must
    // keep behaving identically to the bracket form.
    println(b.get(2L))
}
