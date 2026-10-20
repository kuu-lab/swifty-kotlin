fun <T : String> value(): T = "x" as T
fun choose(value: String): String = value
fun choose(value: Int): String = "int"
fun chooseBoth(first: String, second: String): String = first + second
fun chooseBoth(first: Int, second: Int): String = "int"
class Receiver {
    fun choose(value: String): String = value
    fun choose(value: Int): String = "int"
}
class ExtensionReceiver
fun ExtensionReceiver.choose(value: String): String = value
fun ExtensionReceiver.choose(value: Int): String = "int"
class FallbackReceiver {
    fun choose(value: Int): String = "member"
}
fun FallbackReceiver.choose(value: String): String = value
class Widget(val value: String) {
    constructor(value: Int) : this("int")
}
fun main() {
    val actual: String = choose(value())
    println(actual)
    println(Receiver().choose(value()))
    println(ExtensionReceiver().choose(value()))
    println(FallbackReceiver().choose(value()))
    println(Widget(value()).value)
    println(chooseBoth(value(), value()))
    println(choose(value<String>()))
    val local: String = value()
    println(choose(local))
}
