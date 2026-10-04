// BUG-154: `CASE_INSENSITIVE_ORDER` is a member of the `String` companion
// object (`String.CASE_INSENSITIVE_ORDER`) in real Kotlin, not a top-level
// `kotlin.text.CASE_INSENSITIVE_ORDER`. This case validates behavior parity
// (referential identity, comparison, sorting) against kotlinc; the previous
// top-level-import form was rejected by kotlinc and tracked as DEBT-DIFF-005,
// now resolved.
fun main() {
    val a = String.CASE_INSENSITIVE_ORDER
    val b = String.CASE_INSENSITIVE_ORDER
    println(a === b)
    println(String.CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA"))
    println(listOf("b", "A", "c", "a").sortedWith(String.CASE_INSENSITIVE_ORDER))
}
