// SKIP-DIFF (DEBT-DIFF-008): primitive Number virtual dispatch not yet implemented; tracked as KSP-1540

fun <T : Number> sumOf(a: T, b: T): Double = a.toDouble() + b.toDouble()

fun main() {
    println(sumOf(40, 2))
}
