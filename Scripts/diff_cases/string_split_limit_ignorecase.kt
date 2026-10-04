fun main() {
    println("a,b,c,d".split(",", limit = 2))
    println("aXbXc".split("x", ignoreCase = true))
    println("aXbXcXd".split("x", ignoreCase = true, limit = 2))
    println("one::two::three".split("::", limit = 2))
}
