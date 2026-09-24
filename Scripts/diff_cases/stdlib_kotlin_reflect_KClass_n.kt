// KSP-1324: kotlin.reflect KClass cast / safeCast.
// findAssociatedObject is Kotlin/Native-only (absent from JVM stdlib) and is
// covered by the Sema golden + ReflectFindAssociatedObjectTests instead.
import kotlin.reflect.KClass
import kotlin.reflect.full.cast
import kotlin.reflect.full.safeCast

class Box(val value: Int)
open class Animal
class Dog : Animal()

fun <T : Any> castVia(klass: KClass<T>, value: Any?): T = klass.cast(value)

fun <T : Any> safeCastVia(klass: KClass<T>, value: Any?): T? = klass.safeCast(value)

fun main() {
    println(String::class.cast("hello"))
    println(Int::class.cast(7))
    println(castVia(String::class, "generic"))

    println(String::class.safeCast(1) ?: "null")
    println(Box::class.safeCast(Box(3))?.value)
    println(safeCastVia(Int::class, "nope") ?: "null")

    val klass = String::class
    println(klass.cast("via local"))

    val animal: Animal = Dog()
    println(Dog::class.cast(animal) is Dog)
    println(Animal::class.cast(Dog()) is Animal)
    println(Int::class.safeCast(3.5) ?: "null")

    try {
        Int::class.cast("nope")
        println("missing")
    } catch (e: ClassCastException) {
        println("caught")
    }
}
