interface Thing
class Impl : Thing
class Box<T>(val value: T)

fun choose(value: Box<Thing>, tag: Any?): String = "thing"
fun choose(value: Box<Impl>, tag: String): String = "impl"

fun main() {
    val tag: Any? = null
    println(choose(Box(Impl()), tag))
}

// With a String tag this call is rejected as ambiguous by Kotlin/JVM 2.3.10:
// choose(Box(Impl()), "tag")
