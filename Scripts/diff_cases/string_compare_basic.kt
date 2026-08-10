// KSP-413: String comparison APIs implemented in bundled Kotlin stdlib source
// (compareTo(other, ignoreCase) / contentEquals / equals(other, ignoreCase)).

fun sign(value: Int): Int {
    if (value < 0) return -1
    if (value > 0) return 1
    return 0
}

fun main() {
    println(sign("apple".compareTo("banana", false)))
    println(sign("Apple".compareTo("apple", false)))
    println(sign("Apple".compareTo("apple", true)))
    println(sign("apple".compareTo("APPLE", true)))
    println(sign("abc".compareTo("ab", true)))
    println(sign("ab".compareTo("abc", true)))
    println(sign("".compareTo("", true)))
    println(sign("ABC".compareTo("abd", true)))

    println("Hello".equals("hello", true))
    println("Hello".equals("hello", false))
    println("Hello".equals("Hello", false))

    val nullString: String? = null
    println(nullString.equals(null, true))
    println(nullString.equals("x", true))
    println("x".equals(nullString, true))

    val left: CharSequence = "Kotlin"
    val right: CharSequence = "kotlin"
    println(left.contentEquals(right))
    println(left.contentEquals(right, true))
    println(left.contentEquals(right, false))
    println(left.contentEquals("Kotlin"))

    val nullSequence: CharSequence? = null
    println(nullSequence.contentEquals(null))
    println(nullSequence.contentEquals(left))
    println(left.contentEquals(nullSequence))

    println("abc".contentEquals("abc"))
    println("abc".contentEquals("abcd"))

    val words = mutableListOf("Banana", "apple", "Cherry")
    words.sortWith { a, b -> a.compareTo(b, true) }
    println(words)
}
