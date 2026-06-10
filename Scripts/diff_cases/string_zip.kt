fun main() {
    // Basic zip: same length
    println("abc".zip("XYZ"))

    // Different lengths (shorter truncates)
    println("ab".zip("XYZ").size)
    println("XYZ".zip("ab").size)

    // Empty source
    println("".zip("XYZ").size)

    // Pair access
    val pairs = "abc".zip("XYZ")
    for (p in pairs) {
        println("${p.first}+${p.second}")
    }

    // Transform variant
    val joined = "abc".zip("XYZ") { a, b -> "$a$b" }
    println(joined)

    // CharSequence receiver
    val cs: CharSequence = "hello"
    println(cs.zip("HI").size)
    println(cs.zip("HI") { a, b -> "$a$b" })
}
