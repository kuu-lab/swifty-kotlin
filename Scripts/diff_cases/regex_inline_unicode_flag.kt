fun main() {
    println(Regex("(?U)abc").find("zabc")?.value ?: "none")
    println(Regex("(?u)abc").find("zabc")?.value ?: "none")
    println(Regex("(?iU)abc").find("zABC")?.value ?: "none")
    println(Regex("(?U)\\w+").find("  héllo ")?.value ?: "none")
    println(Regex("(?U)\\d+").find("x٣٤y")?.value ?: "none")
    println(Regex("a(?U:b)c").matches("abc"))
}
