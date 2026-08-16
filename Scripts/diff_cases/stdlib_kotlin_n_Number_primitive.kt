// SKIP-DIFF (KSP-1503): primitive Number virtual dispatch not yet implemented

fun main() {
    val n: Number = 42
    println(n.toInt())
    println(n.toLong())
    println(n.toDouble())
}
