package ch03.javaClassNameMapping

fun main() {
    val boxed: Any = 42
    println(boxed.javaClass.toString())
    println(Int::class.javaPrimitiveType!!.toString())

    val strings = arrayOf("x")
    println(strings.javaClass.toString())
    println(strings.javaClass.kotlin.toString())

    val ints = intArrayOf(1)
    println(ints.javaClass.toString())
    println(ints.javaClass.kotlin.toString())

    println(JavaClassToStringSample().javaClass.toString())
}

class JavaClassToStringSample
