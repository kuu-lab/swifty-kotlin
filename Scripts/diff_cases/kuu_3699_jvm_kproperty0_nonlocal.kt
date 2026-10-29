// DIFF_JVM
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KMutableProperty
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1
import kotlin.reflect.full.IllegalPropertyDelegateAccessException

class Delegate {
    operator fun getValue(receiver: Any?, property: KProperty<*>): String = "delegated"
}
class Box(var value: Int)

var number = 1
val delegated by Delegate()

fun main() {
    val property: KMutableProperty0<Int> = ::number
    println("get=" + property.get())
    println("invoke=" + property.invoke())
    println("delegate=" + (property.getDelegate() == null))
    val getter: KProperty0.Getter<Int> = property.getter
    val setter: KMutableProperty0.Setter<Int> = property.setter
    println("getter-name=" + getter.name)
    println("getter-call=" + getter.call())
    println("getter-invoke=" + getter.invoke())
    println("getter-callBy=" + getter.callBy(emptyMap()))
    println("getter-owner=" + (getter.property == property))
    setter.call(2)
    println("setter-call=" + property.get())
    property.set(3)
    println("set=" + property.get())
    setter.invoke(4)
    println("setter-invoke=" + property.get())
    setter.callBy(mapOf(setter.parameters[0] to 5))
    println("setter-callBy=" + property.get())
    val base: KProperty<Int> = property
    val mutableBase: KMutableProperty<Int> = property
    println("base-getter=" + base.getter.call())
    mutableBase.setter.call(6)
    println("base-setter=" + property.get())
    val box = Box(6)
    val bound = box::value
    println("bound-getter=" + bound.getter.call())
    bound.setter.call(7)
    println("bound-setter=" + box.value)
    val unboundBase: KProperty<Int> = Box::value
    val unboundMutableBase: KMutableProperty<Int> = Box::value
    println("unbound-base-getter=" + unboundBase.getter.call(box))
    unboundMutableBase.setter.call(box, 8)
    println("unbound-base-setter=" + box.value)
    try {
        @Suppress("UNCHECKED_CAST")
        (property as Any as KProperty1<Any?, *>).get(null)
        println("wrong-type=accepted")
    } catch (e: ClassCastException) {
        println("wrong-type=rejected")
    }
    try {
        ::delegated.getDelegate()
        println("private-delegate=accepted")
    } catch (e: IllegalPropertyDelegateAccessException) {
        println("private-delegate=" + e.javaClass.name)
    }
}
