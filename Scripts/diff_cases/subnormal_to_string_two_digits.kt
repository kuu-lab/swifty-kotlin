// DIFF_JVM
// JDK 19+ prints subnormals below 1e-322 (Float: 1e-43) with the closest two-digit decimal.
const val D1 = "" + 1 * Double.MIN_VALUE
const val D2 = "" + 2 * Double.MIN_VALUE
const val D3 = "" + 3 * Double.MIN_VALUE
const val D8 = "" + 8 * Double.MIN_VALUE
const val D10 = "" + 10 * Double.MIN_VALUE
const val D20 = "" + 20 * Double.MIN_VALUE
const val D21 = "" + 21 * Double.MIN_VALUE
const val F1 = "" + 1 * Float.MIN_VALUE
const val F2 = "" + 2 * Float.MIN_VALUE
const val F3 = "" + 3 * Float.MIN_VALUE
const val F5 = "" + 5 * Float.MIN_VALUE
const val F7 = "" + 7 * Float.MIN_VALUE
const val F8 = "" + 8 * Float.MIN_VALUE
const val F21 = "" + 21 * Float.MIN_VALUE
const val F71 = "" + 71 * Float.MIN_VALUE

fun main() {
    println(D1)
    println(D2)
    println(D3)
    println(D8)
    println(D10)
    println(D20)
    println(D21)
    println(F1)
    println(F2)
    println(F3)
    println(F5)
    println(F7)
    println(F8)
    println(F21)
    println(F71)
    for (k in 1..25) println(k * Double.MIN_VALUE)
    for (k in 1..80) println(k * Float.MIN_VALUE)
    println(-2 * Double.MIN_VALUE)
    println(0.0)
    println(0.0f)
}
