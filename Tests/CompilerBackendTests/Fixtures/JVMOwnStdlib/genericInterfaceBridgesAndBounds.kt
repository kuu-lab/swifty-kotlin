interface Transform<T> { fun apply(value: T): T }
class Increment: Transform<Int> { override fun apply(value: Int): Int = value + 1 }
class Echo: Transform<String> { override fun apply(value: String): String = value }
interface Source<T> { fun get(): T }
class IntSource: Source<Int> { override fun get(): Int = 12 }
interface Named { fun name(): String }
class Name: Named { override fun name(): String = "bounded" }
fun <T: Named> same(value: T): T = value
fun <T: Number> number(value: T): Int = value.toInt()
fun main() {
    val increment: Transform<Int> = Increment()
    println(increment.apply(41))
    val echo: Transform<String> = Echo()
    println(echo.apply("bridge"))
    val source: Source<Int> = IntSource()
    println(source.get())
    println(same(Name()).name())
    println(number(42L))
}
