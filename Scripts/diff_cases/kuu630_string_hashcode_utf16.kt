// KUU-630: String.hashCode() is defined over UTF-16 code units with 32-bit
// wrapping accumulation (h = 31*h + unit). A supplementary-plane character
// counts as its surrogate pair (two units), and the running total must wrap
// at Int32 instead of leaking an untruncated 64-bit value.
data class StringHolder(val value: String)

fun main() {
    // "𐀀" is U+10000 → UTF-16 surrogate pair D800 DC00 → 1770496, not the
    // single-Unicode-scalar value 65536.
    println("𐀀".hashCode())
    println("😀".hashCode())

    // Long-enough BMP strings push the accumulator past Int32 range: this
    // must wrap to a negative Kotlin Int rather than return 2870581347.
    println("abcdef".hashCode())
    println("abcdefghijklmnopqrstuvwxyz".hashCode())

    // Structural hashes compose element hashCode()s, so a wrong string hash
    // contaminates collections and data classes too.
    println(listOf("𐀀").hashCode())
    println(setOf("𐀀", "abcdef").hashCode())
    println(mapOf("𐀀" to 1).hashCode())
    println(StringHolder("𐀀").hashCode())

    // An Any-erased receiver still routes through the same string hash.
    val erased: Any = "𐀀"
    println(erased.hashCode())
}
