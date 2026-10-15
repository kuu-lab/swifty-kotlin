// KUU-2175: Kotlin 2.4.20 includes Serializable among boxed primitive KClass supertypes.
import kotlin.reflect.*

fun main() {
    println(Byte::class.supertypes)
    println(Short::class.supertypes)
    println(Int::class.supertypes)
    println(Long::class.supertypes)
    println(Float::class.supertypes)
    println(Double::class.supertypes)
    println(Number::class.supertypes)
    println(Char::class.supertypes)
    println(Boolean::class.supertypes)
    println(String::class.supertypes)
    println(UInt::class.supertypes)
    println(IntArray::class.supertypes)
    val i: Any = 42
    println(i is Number)
    println(i is Comparable<*>)
    println(Number::class.isInstance(i))
    println(Char::class.isInstance(i))
}
