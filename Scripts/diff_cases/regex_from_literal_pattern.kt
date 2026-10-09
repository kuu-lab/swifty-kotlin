fun main() {
    // KUU-648: Regex.fromLiteral keeps the original literal as `.pattern`.
    val r = Regex.fromLiteral("a.b")
    println(r.pattern)
    println(r.toString())
    println(r.options.contains(RegexOption.LITERAL))
    println(r.matches("a.b"))
    println(r.matches("axb"))

    val brackets = Regex.fromLiteral("[a-z]+")
    println(brackets.pattern)
    println(brackets.containsMatchIn("hello"))
    println(brackets.containsMatchIn("[a-z]+"))
}
