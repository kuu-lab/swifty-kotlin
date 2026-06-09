package golden.sema

// STDLIB-REFLECT-067: KClass type-kind boolean introspection properties.

data class Point(val x: Int, val y: Int)
sealed class Shape
enum class Color { RED, GREEN, BLUE }
value class Meters(val value: Double)
interface Printable
object Singleton
inner class Node
fun interface Transformer { fun transform(x: Int): Int }

fun checkTypeKinds(): Boolean {
    val dataCheck = Point::class.isData
    val sealedCheck = Shape::class.isSealed
    val enumCheck = Color::class.isEnum
    val valueCheck = Meters::class.isValue
    val interfaceCheck = Printable::class.isInterface
    val objectCheck = Singleton::class.isObject
    val funCheck = Transformer::class.isFun
    return dataCheck && sealedCheck && enumCheck && valueCheck && interfaceCheck && objectCheck && funCheck
}

fun checkViaVariable(klass: kotlin.reflect.KClass<*>): String {
    return when {
        klass.isData -> "data"
        klass.isSealed -> "sealed"
        klass.isEnum -> "enum"
        klass.isValue -> "value"
        klass.isInterface -> "interface"
        klass.isObject -> "object"
        klass.isFun -> "fun"
        else -> "other"
    }
}
