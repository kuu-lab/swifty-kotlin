// SKIP-DIFF (DEBT-DIFF-008): primitive Number virtual dispatch not yet implemented; tracked as KSP-1540

fun main() {
    val n: Number = 42
    println(n.toInt())
    println(n.toLong())
    println(n.toDouble())
}
