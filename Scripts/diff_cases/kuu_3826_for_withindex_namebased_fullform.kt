// KUU-3826: full-form `for ((val value) in it)` destructuring binds by
// component *name*, not positionally to component1. The for-header parser
// used to silently swallow the `val` keyword, so the entries fell back to
// positional componentN binding (`value` received `index`). Covers the
// discovery shape from
// codegen/box/controlStructures/forInCharSequenceWithIndex/forInStringWithIndexNameBasedDestructuringFullForm.kt
// (test2/test7) plus array/sequence/map variants; the bare short form stays
// positional.
// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring

fun main() {
    // Shorthand full form: `value` binds the property named `value`
    // (component2 of IndexedValue), not component1.
    for ((val value) in "ab".withIndex()) println("t2=$value;")

    // Full form with aliases, deliberately swapped.
    for ((val v = value, val i = index) in "ab".withIndex()) println("t7=$i:$v;")

    // Full form in declaration order.
    for ((val index, val value) in "ab".withIndex()) println("t8=$index:$value;")

    // Array.withIndex and Sequence.withIndex element types share the same
    // IndexedValue members.
    for ((val value) in arrayOf("x", "y").withIndex()) println("arr=$value;")
    for ((val value) in listOf("p", "q").asSequence().withIndex()) println("seq=$value;")

    // Map iteration exposes key/value named properties.
    val m = linkedMapOf("k1" to "v1", "k2" to "v2")
    for ((val key, val value) in m) println("map=$key:$value;")

    // Lambda destructuring full form shares the same fix path.
    val byChar: (IndexedValue<Char>) -> String = { (val value) -> "L$value;" }
    println("lambda=" + "ab".withIndex().map(byChar).joinToString(""))

    // Bare short form keeps positional componentN binding.
    for ((i, x) in "ab".withIndex()) println("pos=$i:$x;")
}
