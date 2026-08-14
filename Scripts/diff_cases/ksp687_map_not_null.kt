// KSP-687 candidate-only coverage: kotlinc's primitive-array mapNotNull surface
// is unavailable in the local reference toolchain, but the bundled source must
// still compile and execute for signed and unsigned primitive arrays.
fun main() {
    val ints = intArrayOf(1, 2, 3)
    println(ints.mapNotNull { if (it % 2 == 0) it.toString() else null })

    val ubytes = UByteArray(3) { (it + 1).toUByte() }
    println(ubytes.mapNotNull { if (it.toInt() > 1) it.toString() else null })
}
