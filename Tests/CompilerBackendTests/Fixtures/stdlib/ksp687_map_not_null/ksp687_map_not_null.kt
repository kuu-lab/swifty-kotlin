// KSP-687 candidate-only coverage: JVM kotlinc has no primitive-array mapNotNull API.
// The fixture runner compiles this bundled-source case and checks its stdout.
@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

fun main() {
    val ints = intArrayOf(1, 2, 3)
    println(ints.mapNotNull { if (it % 2 == 0) it.toString() else null })

    val ubytes = UByteArray(3) { (it + 1).toUByte() }
    println(ubytes.mapNotNull { if (it.toInt() > 1) it.toString() else null })
}
