fun main() {
    // Basic concatToString
    val chars = charArrayOf('H', 'e', 'l', 'l', 'o')
    println(chars.concatToString())

    // Empty CharArray
    val empty = charArrayOf()
    println(empty.concatToString())
    println(empty.concatToString().isEmpty())

    // Single character
    val single = charArrayOf('A')
    println(single.concatToString())

    // Round-trip: String -> CharArray -> String
    val original = "Kotlin"
    val roundTripped = original.toCharArray().concatToString()
    println(roundTripped)

    // Special characters
    val special = charArrayOf('\n', '\t', '\\', '\'')
    println(special.concatToString().length)

    // Digits
    val digits = charArrayOf('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
    println(digits.concatToString())

    // Unicode characters
    val unicode = charArrayOf('\u0048', '\u0065', '\u006C', '\u006C', '\u006F')
    println(unicode.concatToString())

    // concatToString result used in string operations
    val greeting = charArrayOf('H', 'i')
    println(greeting.concatToString() + " there")
    println(greeting.concatToString().length)

    // Surrogate pairs: CharArray holds UTF-16 code units, so a pair must
    // recombine into one supplementary-plane character (KUU-634).
    val surrogate = charArrayOf('\uD800', '\uDC00')
    println(surrogate.concatToString())
    println(surrogate.concatToString().length)

    // String -> CharArray -> String round-trip keeps supplementary chars
    val astral = "𐀀"
    println(astral.toCharArray().concatToString() == astral)
    println(astral.toCharArray().concatToString().length)

    // Isolated surrogate keeps its UTF-16 code unit
    val lone = charArrayOf('x', '\uD800', 'y')
    println(lone.concatToString().length)
    println(lone.concatToString()[1].code)
}
