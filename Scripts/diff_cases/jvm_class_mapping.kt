import kotlin.reflect.KClass

fun mapped(type: java.lang.Class<String>): KClass<String> = type.kotlin
fun primitive(type: KClass<Int>): java.lang.Class<Int>? = type.javaPrimitiveType
fun <T : Any> generic(type: java.lang.Class<T>): KClass<T> = type.kotlin

class MappingSample

fun main() {
    println(mapped("value".javaClass) == String::class)
    val integer = primitive(Int::class)
    println(integer != null)
    println(integer!!.kotlin == Int::class)
    println(integer === primitive(Int::class))
    println(generic(integer) == Int::class)
    val erased: Any = integer
    println(erased is java.lang.Class<*>)
    println((erased as java.lang.Class<Int>).kotlin == Int::class)
    println(Boolean::class.javaPrimitiveType!!.kotlin == Boolean::class)
    println(Byte::class.javaPrimitiveType!!.kotlin == Byte::class)
    println(Short::class.javaPrimitiveType!!.kotlin == Short::class)
    println(Long::class.javaPrimitiveType!!.kotlin == Long::class)
    println(Char::class.javaPrimitiveType!!.kotlin == Char::class)
    println(Float::class.javaPrimitiveType!!.kotlin == Float::class)
    println(Double::class.javaPrimitiveType!!.kotlin == Double::class)
    println(String::class.javaPrimitiveType == null)
    println(Unit::class.javaPrimitiveType == null)
    println(UInt::class.javaPrimitiveType == null)
    println(MappingSample::class.javaPrimitiveType == null)
    println(MappingSample().javaClass.kotlin == MappingSample::class)
    println(Nothing::class.javaPrimitiveType != null)
    println(Nothing::class.javaPrimitiveType!!.kotlin == Nothing::class)
    try {
        String::class.javaPrimitiveType!!
        println("unexpected")
    } catch (e: NullPointerException) {
        println("null rejected")
    }
}
