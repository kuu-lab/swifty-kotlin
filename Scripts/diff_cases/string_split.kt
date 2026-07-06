fun main() {
    println("a,b,c".split(","))
    println("a,b,c,d".split(",", limit = 2))
    println("aXbxc".split("x", ignoreCase = true))
    println("aXbxc".split("x", ignoreCase = true, limit = 2))
    println("a,b,c".splitToSequence(",").toList())
}
