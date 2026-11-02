// KUU-4018: array class literals carry per-element identity like the JVM
// (`Array<Int>::class != Array<String>::class`) while names and primitive
// arrays keep their nominal behaviour.
package kclassarrayid

fun main() {
    println(Array<Int>::class.qualifiedName)
    println(Array<Int>::class.simpleName)
    println(Array<Int>::class == Array<String>::class)
    println(Array<Int>::class == Array<Int>::class)
    println(Array<Int?>::class == Array<Int>::class)
    println(IntArray::class == IntArray::class)
    println(Array<Int>::class.isInstance(arrayOf(1)))
    println(Array<Int>::class.isInstance(arrayOf("x")))
    println(Array<Int>::class.isInstance(42))
    println(Array<Int>::class.isInstance(null))
    println(IntArray::class.isInstance(intArrayOf(1)))
    println(IntArray::class.isInstance(arrayOf(1)))
    println(arrayOf(1)::class == Array<Int>::class)
    println(arrayOf("a")::class == Array<String>::class)
    println(arrayOf(1)::class == Array<String>::class)
    println(intArrayOf(1)::class == IntArray::class)
    println(Array<Array<Int>>::class == Array<Array<String>>::class)
    println(Array<Array<Int>>::class == Array<Array<Int>>::class)
    println(Array<Array<Int>>::class.isInstance(arrayOf(arrayOf(1))))
    println(Array<Array<String>>::class.isInstance(arrayOf(arrayOf(1))))
    println(Array<Any>::class.isInstance(arrayOf(1)))
    println(Array<Int>::class.isInstance(arrayOf<Any>(1)))
    println(classOf<Array<Int>>() == Array<Int>::class)
    println(classOf<Array<Int>>() == Array<String>::class)
    println(classOf<IntArray>() == IntArray::class)
    println(classOf<Array<Int>>() == Array<Int?>::class)
    println(genericArrayClass<Any>() == genericArrayClass<String>())
    println(genericArrayClass<Int>() == Array<Int>::class)
}

inline fun <reified T> classOf() = T::class
inline fun <reified T> genericArrayClass() = Array<T>::class
