// KUU-3835: the full form `(val a, var b) = x` is unambiguously name-based —
// its entries declare val/var — so it binds member properties by name without
// requiring componentN operators or a feature flag. Previously a type with no
// componentN was rejected with SEMA-0086.
// KOTLINC_FLAGS: -XXLanguage:+NameBasedDestructuring -XXLanguage:+DeprecateNameMismatchInShortDestructuringWithParentheses -XXLanguage:+EnableNameBasedDestructuringShortForm

sealed interface Subject
class IntEntry(val value: Int) : Subject
class Tuple(val first: String, val second: Int)

fun main() {
    val subject: Subject = IntEntry(1)
    if (subject is IntEntry) {
        (val value: Int) = subject
        println(value)
    }

    (val first, var second) = Tuple("x", 22)
    second = 23
    println("$first,$second")

    (val s = second) = Tuple("y", 33)
    println(s)
}
