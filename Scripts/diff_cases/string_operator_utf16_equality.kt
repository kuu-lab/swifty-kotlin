// KUU-625: String == / != must compare UTF-16 code units, not Swift's
// Unicode-canonical-equivalent String equality.
fun main() {
    val composed = "\u00E9"      // U+00E9
    val decomposed = "e\u0301"   // U+0065 U+0301
    val decomposedLiteral = "é" // U+0065 U+0301 written directly

    println(composed == decomposed)
    println(composed != decomposed)
    println(composed.equals(decomposed))
    println(composed == decomposedLiteral)
}
