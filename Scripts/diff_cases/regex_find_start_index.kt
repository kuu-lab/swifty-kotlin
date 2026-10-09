fun main() {
    println(Regex("b").find("abc", 2))
    println(Regex("a").findAll("aaa", 1).count())
}
