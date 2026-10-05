// KUU-1264: KClass rendering must use the represented type's qualified name.
package kuu1264

import kotlin.reflect.KClass
import kotlin.reflect.typeOf

class Sample

fun renderClass(klass: KClass<*>): String = klass.toString()

fun main() {
    println(String::class.toString())
    println(Int::class.toString())
    println(String::class)
    val klass: KClass<*> = Sample::class
    println(klass.toString())
    println(klass)
    println(renderClass(String::class))
    val erased: Any = Int::class
    println(erased.toString())
    println(erased)
    println("class=$klass")
    println(listOf(String::class, Int::class, Sample::class))
    println(String::class.simpleName)
    println(String::class.qualifiedName)
    println(String::class.isInstance("value"))
    println(String::class == String::class)
    println(String::class.hashCode() == String::class.hashCode())
    println(typeOf<List<String>>())
}
