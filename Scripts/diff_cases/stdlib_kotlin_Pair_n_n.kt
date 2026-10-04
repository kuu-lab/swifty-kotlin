fun main() {
    val pair = Pair(42, "answer")
    println(pair)
    println(pair.first)
    println(pair.second)

    val nullable: Pair<String?, Int?> = Pair(null, null)
    println(nullable)
    println(nullable.first)
    println(nullable.second)
}
