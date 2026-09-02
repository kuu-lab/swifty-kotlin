fun main() {
    val match = Regex("(a)(b)?(c)(d)(e)(f)(g)(h)(i)(j)").find("acdefghij")
    if (match != null) {
        val destructured = match.destructured
        val captures = destructured.toList()
        println(destructured.component10())
        println(captures)
        println(captures.size)
    }
}
