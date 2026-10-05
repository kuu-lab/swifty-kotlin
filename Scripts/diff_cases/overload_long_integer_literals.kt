fun g(): Long = 0
fun g(l: Long): Long = l + 2
fun h(l: Long): Long = l + 1

class LongOverloads {
    fun f(): Long = 0
    fun f(l: Long): Long = l + 1
    fun f(a: Long, b: Long): Long = a + b
}

fun LongOverloads.extension(): Long = 0
fun LongOverloads.extension(value: Long): Long = value + 3

fun pick(value: Int): String = "Int"
fun pick(value: Long): String = "Long"
fun mixed(value: Int, tag: String): String = "Int:$tag"
fun mixed(value: Long, tag: String): String = "Long:$tag"

fun defaulted(tag: String = "tag", value: Long): Long = value
fun defaulted(value: String): Long = 0
fun nullable(value: Long?): Long? = value
fun nullable(value: String): Long? = null

fun main() {
    println(h(100))
    println(g())
    println(g(100))
    println(g(l = 100))
    println(g(-100))
    println(g(+100))
    println(g(100L))
    val x = LongOverloads()
    println(x.f())
    println(x.f(100))
    println(x.f(50, 60))
    println(x.f(b = 60, a = 50))
    println(x.extension(100))
    println(defaulted(value = 100))
    println(nullable(100))
    println(pick(100))
    println(pick(100L))
    println(mixed(100, "literal"))
    println(mixed(100L, "literal"))
    val intValue: Int = 100
    val longValue: Long = 100
    println(pick(intValue))
    println(pick(longValue))
    val random = kotlin.random.Random(42)
    val until = random.nextLong(100)
    println(until >= 0L && until < 100L)
    val bounded = random.nextLong(50, 60)
    println(bounded >= 50L && bounded < 60L)
    val named = random.nextLong(until = 60, from = 50)
    println(named >= 50L && named < 60L)
}
