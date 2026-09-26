fun main() {
    // Zero-width matches with a positive limit (KUU-635)
    println("abc".split(Regex("x*"), 3))
    println("a1b".split(Regex("\\d*"), 5))
    println("abc".split(Regex(""), 3))
    println("aba".split(Regex("a?"), 4))

    // The unbounded form must agree with the limited form's prefix
    println("abc".split(Regex("x*")))
    println("a1b".split(Regex("\\d*")))
    println("abc".split(Regex("")))

    // Ordinary limit semantics
    println("a,b,c".split(Regex(","), 2))
    println("ab".split(Regex("b"), 1))
    println(Regex("b").split("ab", 2))

    // Negative limit throws IllegalArgumentException
    try {
        println("ab".split(Regex("b"), -1))
    } catch (e: IllegalArgumentException) {
        println("IAE: " + e.message)
    }
    try {
        println(Regex("b").split("ab", -2))
    } catch (e: IllegalArgumentException) {
        println("IAE: " + e.message)
    }
}
