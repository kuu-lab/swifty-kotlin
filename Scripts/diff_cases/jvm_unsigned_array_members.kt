// DIFF_JVM
// Unsigned arrays support toList/isEmpty/isNotEmpty like their signed peers.
fun main() {
    println(uintArrayOf(3u, 1u).toList())
    println(uintArrayOf(3u, 1u).isEmpty())
    println(uintArrayOf().isNotEmpty())
    println(ubyteArrayOf(1u).toList())
    println(ulongArrayOf(1uL).isNotEmpty())
    println(ushortArrayOf(1u).isEmpty())
}
