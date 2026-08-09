// KSP-496: KClass.cast / KClass.safeCast as bundled Kotlin extensions
import kotlin.reflect.KClass
import kotlin.reflect.full.cast
import kotlin.reflect.full.safeCast

class Box(val value: Int)

fun <T : Any> castVia(klass: KClass<T>, value: Any?): T = klass.cast(value)

fun main() {
    println(String::class.cast("hello"))
    println(Int::class.cast(7))
    println(castVia(String::class, "generic"))

    println(String::class.safeCast(1))
    println(Box::class.safeCast(Box(3))?.value)

    val klass = String::class
    println(klass.cast("via local"))

    try {
        Int::class.cast("nope")
    } catch (e: ClassCastException) {
        println("caught")
    }
}
