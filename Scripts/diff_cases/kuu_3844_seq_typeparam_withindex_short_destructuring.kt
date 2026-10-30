// KUU-3844: `sequence.withIndex()` on a `T : Sequence<*>` receiver previously
// lowered to a bare `withIndex` extern that failed to link (LINK-0001). The
// unresolved-member sequence fallback was fixed by KUU-3202; this case pins
// the upstream discovery shape (name-based destructuring short form over a
// generic Sequence receiver) from
// codegen/box/controlStructures/forInSequenceWithIndex/forInSequenceTypeParameterWithIndex.kt.
// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring -XXLanguage:+DeprecateNameMismatchInShortDestructuringWithParentheses -XXLanguage:+EnableNameBasedDestructuringShortForm

val xs = listOf("a", "b", "c", "d").asSequence()

fun <T : Sequence<*>> test(sequence: T): String {
    val s = StringBuilder()

    for ([index, x] in sequence.withIndex()) {
        s.append("$index:$x;")
    }

    return s.toString()
}

fun box(): String {
    val ss = test(xs)
    return if (ss == "0:a;1:b;2:c;3:d;") "OK" else "fail: '$ss'"
}

fun main() = println(box())
