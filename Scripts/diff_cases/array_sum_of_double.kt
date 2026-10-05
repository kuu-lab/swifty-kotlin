// KUU-1226: Inline selector results must be unboxed before Double arithmetic.
fun main() {
    val values = arrayOf("a", "bb", "ccc")
    println(values.sumOf { it.length.toDouble() })
    val selector: (String) -> Double = { it.length.toDouble() / 2.0 - 1.25 }
    println(values.sumOf(selector))
    val offset = 0.25
    println(values.sumOf { if (it.length > 1) it.length.toDouble() + offset else -0.5 })
    println(emptyArray<String>().sumOf { it.length.toDouble() })
    println(arrayOf(-1.5, 0.25, 2.0).sumOf { it })
}
