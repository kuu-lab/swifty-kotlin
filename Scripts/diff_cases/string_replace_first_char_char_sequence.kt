fun main() {
    println("hello".replaceFirstChar { it.uppercase() })
    println("hello".replaceFirstChar { it.uppercaseChar() })
    println("hello".replaceFirstChar(Char::titlecase))
}
