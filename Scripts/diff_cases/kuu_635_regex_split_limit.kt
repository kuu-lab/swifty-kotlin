fun main() {
    // KUU-635: Regex.split(input, limit) with zero-width matches must add the
    // pre-match segment (possibly empty), not the next character.
    println("abc".split(Regex("x*"), 3))
    println("a1b".split(Regex("\\d*"), 5))
    println("abc".split(Regex(""), 3))
    println("abc".split(Regex("a?"), 4))
    println("axbxc".split(Regex("x*"), 4))
    println("xxx".split(Regex("x*"), 2))
    println("".split(Regex("x*"), 3))

    // limit == 0 path stays consistent with limited splits
    println("abc".split(Regex("x*")))
    println("abc".split(Regex("x*"), 1))
    println("abc".split(Regex("x*"), 2))

    // CharSequence receiver and direct Regex.split
    val cs: CharSequence = "abc"
    println(cs.split(Regex("x*"), 3))
    println(Regex("-").split("a-b-c", 2))

    // Non-zero-width sanity
    println("a,b,c".split(Regex(","), 2))
    println("abc".split(Regex("b"), 1))

    // KUU-635: negative limit throws IllegalArgumentException
    try {
        "ab".split(Regex("b"), -1)
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        println(Regex("b").split("ab", -2))
        println("no-throw2")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        println(Regex("b").splitToSequence("ab", -1).toList())
        println("no-throw3")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        println(cs.split(Regex("b"), -1))
        println("no-throw4")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
