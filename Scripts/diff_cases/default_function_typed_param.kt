fun trailing(n: Int = 1, block: (Int) -> String = { "d$it" }) = block(n)

fun withCapture(prefix: String, f: (String) -> String = { prefix + it }) = f("!")

fun main() {
    println(trailing())
    println(trailing(5))
    println(trailing { "x$it" })
    println(trailing(2) { "y$it" })
    println(withCapture("p"))
}
