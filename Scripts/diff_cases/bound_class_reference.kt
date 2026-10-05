import kotlin.reflect.KClass

open class BoundBase {
    fun classNameFromThis(): String? = this::class.simpleName
}
class BoundDerived : BoundBase()
class BoundFoo
interface BoundMarker
class BoundMarked : BoundMarker
enum class BoundEnum { FIRST }

var boundEvaluations = 0
fun makeBoundFoo(): BoundFoo {
    boundEvaluations++
    return BoundFoo()
}
fun <T : Any> boundClassOf(value: T): KClass<out T> = value::class
fun boundName(value: Any): String? = value::class.simpleName
fun <T> assertedBoundName(value: T): String? = value!!::class.simpleName
fun <T> guardedBoundName(value: T): String? {
    if (value != null) return value::class.simpleName
    return null
}
fun <T> narrowedBoundName(value: T): String? {
    value!!
    return value::class.simpleName
}

fun main() {
    val f = BoundFoo()
    println(f::class.simpleName)
    println(1::class.simpleName)
    println("x"::class.simpleName)
    val erased: Any = "s"
    println(erased::class.simpleName)
    println(boundName(1))
    println(boundName(1L))
    println(boundName(1.toByte()))
    println(boundName(1.toShort()))
    println(boundName(1.5))
    println(boundName(1.5f))
    println(boundName(true))
    println(boundName('x'))
    println(boundName(1u))
    println(boundName(1uL))
    println(boundName(1.toUByte()))
    println(boundName(1.toUShort()))
    println(boundName(Unit))
    val enumValue: Any = BoundEnum.FIRST
    println(enumValue::class.simpleName)
    println(enumValue::class == BoundEnum::class)
    println(boundClassOf("s").simpleName)
    println(boundClassOf(f).simpleName)
    println(assertedBoundName("s"))
    println(guardedBoundName("s"))
    println(narrowedBoundName("s"))
    val base: BoundBase = BoundDerived()
    val marker: BoundMarker = BoundMarked()
    println(base::class.simpleName)
    println(base.classNameFromThis())
    println(marker::class.simpleName)
    println(base::class == BoundDerived::class)
    println(erased::class == String::class)
    val stored = f::class
    println(stored == BoundFoo::class)
    println(stored.isInstance(f))
    println((if (true) f else BoundFoo())::class.simpleName)
    println(makeBoundFoo()::class.simpleName)
    println(boundEvaluations)
    val BoundFoo = f
    println(BoundFoo::class.simpleName)
    val nullable: BoundBase? = base
    println(nullable!!::class.simpleName)
}
