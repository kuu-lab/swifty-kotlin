// Unicode edge cases: lone surrogate halves in Char case conversion, simple
// (not full) case mapping, Char-wise ignoreCase replace, Final_Sigma, split by
// UTF-16 code units, and surrogate-safe commonPrefixWith/commonSuffixWith.
fun main() {
    // Char.uppercase/lowercase/titlecase on a surrogate half is the identity.
    val emoji = "😀x"
    println(emoji[0].uppercase()[0].code)
    println(emoji[1].lowercase()[0].code)
    println(emoji.replaceFirstChar { it.titlecase() } == emoji)

    // uppercaseChar/lowercaseChar use the simple mapping.
    println('İ'.lowercaseChar().code)
    println('ᾀ'.uppercaseChar().code)
    println('ß'.uppercaseChar().code)
    println("İ".equals("i", ignoreCase = true))

    // replace(Char, Char, ignoreCase) compares like Char.equals(ignoreCase).
    println("ςσΣ".replace('σ', '*', ignoreCase = true))
    println("ıi".replace('i', '*', ignoreCase = true))

    // Final_Sigma.
    println("ΟΔΟΣ".lowercase())
    println("Σ".lowercase())
    println("ΣΟ".lowercase())
    println("ΟΣ Ο".lowercase())

    // split compares UTF-16 code units: no canonical equivalence, no full folding.
    println("café".split("é").size)
    println("café".split("é").size)
    println("café".split("é").size)
    println("straße".split("SS", ignoreCase = true).size)
    println("aéb".split("é").size)
    println("a,b,,c".split(",").size)
    println("a,b,,c".split(",", limit = 2))
    println("aXbxc".split("x", ignoreCase = true))

    // commonPrefixWith/commonSuffixWith never split a surrogate pair.
    println("x😀".commonPrefixWith("x😁").length)
    println("a🈀".commonSuffixWith("b😀").length)
    println("ab😀".commonPrefixWith("ab😀c"))
}
