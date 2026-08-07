fun main() {
    val concatenated = "he" + "llo"
    println(concatenated is CharSequence)
    println(StringBuilder("x").toString() is CharSequence)
    println(buildString { append("y") } is CharSequence)
    println(concatenated is Comparable<*>)
    val erased: Any = concatenated
    println(erased is CharSequence)
    println(erased is List<*>)
    println("literal" is CharSequence)
}
