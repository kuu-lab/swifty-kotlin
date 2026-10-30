fun <T> perform(action: () -> T): T = action()
fun <T> identity(value: T): T = value

fun main() {
    var number = 0
    val block: () -> Unit = { perform { number++ } }
    block()
    println("count=$number")
    val integer: Int = perform { 42 }
    println("value=$integer")
    val plain: () -> Unit = { 123 }
    println(plain() == Unit)
    try {
        val invalid: Any = identity<Any>(42)
        println(invalid as Unit)
    } catch (e: ClassCastException) {
        println("wrong type")
    }
}
