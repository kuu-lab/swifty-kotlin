// DIFF_JVM
fun main() {
    // KUU-3918: Regex.matches is `infix` in the Kotlin stdlib.
    val digits = Regex("[0-9]+")
    println(digits matches "123")
    println(digits matches "abc")
    println(digits.matches("456"))

    // Ktor RegexParser shape: `expression matches input` inside a condition.
    val expression = Regex("[a-z]+")
    val input = "abc"
    println(if (expression matches input) "match" else "no-match")

    // Upstream `String.matches(regex)` / `CharSequence.matches(regex)` are
    // also `infix`; the bundled String overload now carries the modifier too.
    println("abc" matches Regex("[a-z]+"))
    println(StringBuilder("abc") matches Regex("[a-z]+"))

    // IntProgression.step is `infix` upstream; the JVM backend source set
    // had dropped the modifier.
    for (i in 1..6 step 2) println(i)
}
