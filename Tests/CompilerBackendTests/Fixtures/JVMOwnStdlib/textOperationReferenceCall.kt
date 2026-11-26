fun main() {
    val unbound = String::codePointAt
    println(unbound("abc", 1))
    println(unbound.call("abc", 1))
    println("abc"::codePointAt.call(2))
    println(String::trimIndent.call("  x"))
    println(unbound.name)
}
