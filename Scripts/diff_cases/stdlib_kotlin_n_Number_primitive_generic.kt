// SKIP-DIFF (KSP-1540): primitive Number virtual dispatch not yet implemented

fun <T : Number> sumOf(a: T, b: T): Double = a.toDouble() + b.toDouble()

fun main() {
    println(sumOf(40, 2))
}
