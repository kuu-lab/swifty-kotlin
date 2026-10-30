// KUU-1303: names must survive standalone class literals without construction.
package reflectionnames

import kotlin.reflect.KClass
import kotlin.reflect.typeOf

class Outer { class Inner }
class RuntimeException
object Named
class Holder { companion object }

@OptIn(ExperimentalStdlibApi::class)
fun main() {
    val exception = kotlin.RuntimeException::class
    val list = List::class
    val ints = IntArray::class
    val pair = Pair::class
    val nothing = Nothing::class
    println(exception.qualifiedName)
    println(list.qualifiedName)
    println(ints.qualifiedName)
    println(pair.qualifiedName)
    println(nothing.qualifiedName)
    println(nothing.simpleName)
    println(String::class.qualifiedName)
    println(Int::class.qualifiedName)
    println(Unit::class.qualifiedName)
    println(Outer.Inner::class.qualifiedName)
    println(Map.Entry::class.qualifiedName)
    println(Array<Int>::class.qualifiedName)
    println(Array<Int>::class.simpleName)
    println(Array<Array<String>>::class.qualifiedName)
    println(RuntimeException::class.qualifiedName)
    println((typeOf<Unit>().classifier as KClass<*>).qualifiedName)
    println(Named::class.qualifiedName)
    println(Holder.Companion::class.qualifiedName)
    class Local
    val anonymous = object {}
    println(Local::class.qualifiedName)
    println(anonymous::class.qualifiedName)
}
