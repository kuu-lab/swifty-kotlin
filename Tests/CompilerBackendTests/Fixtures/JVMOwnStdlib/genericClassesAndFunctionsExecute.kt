class Box<T>(var value: T) { fun get(): T = value }
fun <T> identity(value: T): T = value
fun <T: Any> bounded(value: T): T = value
fun <T: Any> maybe(value: T?): T? = value
fun main() {
    val text = Box<String>("hello")
    println(text.get())
    text.value = "changed"
    println(text.value)
    val number = Box(21)
    println(number.get() * 2)
    println(identity<Int>(7))
    println(identity("inferred"))
    println(bounded("bound"))
    println(maybe<String>(null))
    val optional: Int? = 8
    println(optional!! + 1)
    println(optional == 8)
    println(maybe<Int>(null) ?: 7)
    val nan: Double? = 0.0 / 0.0
    val zero: Double? = -0.0
    println(nan == nan)
    println(zero == 0.0)
    val erased: Any? = nan
    println(erased == nan)
}
