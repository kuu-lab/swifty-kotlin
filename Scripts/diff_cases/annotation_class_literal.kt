package annotations

import annotations.MyAnno
import annotations.MyAnno as Alias
import kotlin.reflect.KClass

annotation class MyAnno(val name: String)
annotation class Marker
class RegularClass

fun annotationClass(): KClass<MyAnno> = MyAnno::class
fun className(klass: KClass<MyAnno>): String? = klass.simpleName

fun main() {
    println(MyAnno::class.simpleName)
    println(MyAnno::class.qualifiedName)
    println(Alias::class.simpleName)
    println(Marker::class.simpleName)
    println(className(MyAnno::class))
    println(annotationClass().simpleName)
    val stored: KClass<MyAnno> = MyAnno::class
    println(stored.simpleName)
    println(stored.qualifiedName)
    println(RegularClass::class.simpleName)
    println(RegularClass::class.qualifiedName)
    println(String::class.simpleName)
    println(String::class.qualifiedName)
}
