fun main() {
    val s = "a1b2c3"

    println(s.firstNotNullOf { c -> if (c.isDigit()) c.digitToInt() else null })
    println(s.firstNotNullOfOrNull { c -> if (c.isDigit()) c.digitToInt() else null })
    println(s.firstNotNullOfOrNull { c -> if (c.isUpperCase()) c else null })

    try {
        s.firstNotNullOf { c -> if (c.isUpperCase()) c else null }
    } catch (e: NoSuchElementException) {
        println("firstNotNullOf none: ${e.message}")
    }
}
