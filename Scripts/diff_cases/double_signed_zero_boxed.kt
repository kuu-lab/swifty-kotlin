// BUG-162: a boxed Double holding -0.0 must not be mistaken for null
// (-0.0's bit pattern is the runtime's null sentinel, Int64.min).
fun main() {
    println(listOf(0.0, -0.0, 2.0).joinToString(","))
    println(listOf(0.0, -0.0, 2.0).sorted().joinToString(","))

    val boxed: Any = -0.0
    println(boxed)

    val nullable: Double? = -0.0
    println(nullable)
    println(listOf<Double?>(-0.0, null, 1.0))

    println(mapOf("neg" to -0.0)["neg"])
    println(mapOf(-0.0 to "neg")[-0.0])

    println(listOf(-0.0).contains(-0.0))
    println(listOf(-0.0).contains(0.0))
    println(listOf(0.0).contains(-0.0))
    println(listOf(-0.0).indexOf(-0.0))
    println(arrayOf(-0.0).contains(-0.0))
    println(listOf(1.0).contains(1.0))
    println(listOf(Double.NaN).contains(Double.NaN))
    println(setOf(-0.0, 0.0).size)

    println(listOf(-0.0f, 0.0f).joinToString(","))
    println(listOf(-0.0f).contains(-0.0f))

    println(listOf(Long.MIN_VALUE, 1L).joinToString(","))
}
