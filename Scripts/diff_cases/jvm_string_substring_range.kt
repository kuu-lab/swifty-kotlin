// DIFF_JVM
// String.substring(range: IntRange) delegates to the (start, endExclusive)
// overload, matching kotlin.text's declaration.
fun main() {
    println("world".substring(1..3))
    println("kotlin".substring(0..0))
    val r = 2..4
    println("abcdef".substring(r))
}
