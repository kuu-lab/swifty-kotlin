import kotlin.reflect.KMutableProperty
import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import java.lang.invoke.MethodHandles
import java.lang.invoke.MethodType

var number = 3

fun readBase(property: KProperty<Int>): Int = property.getter.call()
fun writeBase(property: KMutableProperty<Int>, value: Int) { property.setter.call(value) }
fun readZero(property: KProperty0<Int>): Int = property.getter.call()
fun writeZero(property: KMutableProperty0<Int>, value: Int) { property.setter.call(value) }

class ExternalProperty(private val delegate: KMutableProperty0<Int>) : KMutableProperty0<Int> by delegate

fun main() {
    val property = ::number
    println("base-get=" + readBase(property))
    writeBase(property, 4)
    println("zero-get=" + readZero(property))
    writeZero(property, 5)
    println("final=" + number)
    val external = ExternalProperty(property)
    val getterLookup = MethodHandles.privateLookupIn(KProperty0::class.java, MethodHandles.lookup())
    val getter = getterLookup.findSpecial(
        KProperty0::class.java, "getGetter", MethodType.methodType(KProperty.Getter::class.java), KProperty0::class.java
    ).bindTo(external).invokeWithArguments() as KProperty.Getter<*>
    println("interface-default-getter=" + getter.call())
    val setterLookup = MethodHandles.privateLookupIn(KMutableProperty0::class.java, MethodHandles.lookup())
    val setter = setterLookup.findSpecial(
        KMutableProperty0::class.java, "getSetter", MethodType.methodType(KMutableProperty.Setter::class.java), KMutableProperty0::class.java
    ).bindTo(external).invokeWithArguments() as KMutableProperty.Setter<*>
    setter.call(6)
    println("interface-default-setter=" + number)
}
