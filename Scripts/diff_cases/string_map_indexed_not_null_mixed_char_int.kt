// KUU-1989: Preserve each branch's primitive type in an erased transform result.
fun main() {
    val digits = mapOf("six" to 6)
    val inferred = "7s".mapIndexedNotNull { _, c ->
        if (c.isDigit()) c else listOf("six").firstNotNullOfOrNull { digits[it] }
    }
    println(inferred.joinToString())
    val explicit: List<Any> = "7s".mapIndexedNotNull { _, c ->
        if (c.isDigit()) c else listOf("six").firstNotNullOfOrNull { digits[it] }
    }
    println(explicit.joinToString())
    println(inferred[0] is Char)
    println(inferred[1] is Int)
    println(explicit[0] is Char)
    println(explicit[1] is Int)
    println("7sx".mapIndexedNotNull { _, c -> if (c.isDigit()) c else digits[c.toString()] }.joinToString())
    println("7s".mapIndexedNotNull { _, c -> if (c.isDigit()) null else digits["six"] }.joinToString())
    println("7s".mapIndexedNotNull { _, c -> if (c.isDigit()) c else null }.joinToString())
}
