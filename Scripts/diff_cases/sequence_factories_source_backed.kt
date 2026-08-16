// KSP-651: source-backed sequence factory overloads and lifecycle semantics.
fun main() {
    val repeated = generateSequence({
        10
    }) { if (it > 1) it / 2 else null }
    println(repeated.toList())

    val nullSeed: Int? = null
    println(generateSequence(nullSeed) { it + 1 }.toList())
}
