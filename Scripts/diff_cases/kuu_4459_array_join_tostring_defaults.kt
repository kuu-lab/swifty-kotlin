// DIFF_JVM
fun display(x: Any?): String = "d$x"

fun main() {
    val star: Array<*> = arrayOf<Any?>(1, "two")
    println(star.joinToString(prefix = "[", postfix = "]", transform = { "y$it" }))
    println(star.joinToString(prefix = "[", transform = ::display))
    println(star.joinToString(postfix = "]", transform = { "z$it" }))
    println(star.joinToString(limit = 1, transform = { "l$it" }))

    val ints: Array<Int> = arrayOf(1, 2)
    println(ints.joinToString(prefix = "[", postfix = "]", transform = { "y$it" }))
    println(ints.joinToString(",", "[", "]") { "t$it" })
    println(ints.joinToString(",", "[", "]", 1, "...") { "t$it" })

    println(star.joinToString())
    println(star.joinToString(prefix = "[", postfix = "]"))
    println(star.joinToString(transform = { "y$it" }))
    println(star.joinToString(separator = ",", transform = ::display))
    println(star.joinToString(separator = ",", prefix = "<", transform = ::display))
}
