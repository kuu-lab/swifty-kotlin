fun main() {
    println("hello".replaceFirstChar { it.uppercase() })
    println("hello".replaceFirstChar { it.uppercaseChar() })
    println("hello".replaceFirstChar(Char::titlecase))

    // KUU-654: Char.lowercase()/uppercase() return String, so they must bind to
    // replaceFirstChar((Char) -> CharSequence).
    println("aBc".replaceFirstChar { it.lowercase() })
    println("aBc".replaceFirstChar { it.uppercase() })
    println("".replaceFirstChar { it.lowercase() })
    println("x".replaceFirstChar { "YY" })
    println("aBc".replaceFirstChar { it.lowercaseChar() })
}
