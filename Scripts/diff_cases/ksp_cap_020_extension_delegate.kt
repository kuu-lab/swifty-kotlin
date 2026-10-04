import kotlin.reflect.KProperty

class Holder(val value: String)

operator fun Holder.getValue(thisRef: Any?, property: KProperty<*>): String = value

class MutableHolder(var value: String)

operator fun MutableHolder.getValue(thisRef: Any?, property: KProperty<*>): String = value
operator fun MutableHolder.setValue(thisRef: Any?, property: KProperty<*>, value: String) {
    this.value = value
}

val readOnly: String by Holder("extension")
var mutable: String by MutableHolder("before")

class GenericHolder<T>(val value: T)

operator fun <T> GenericHolder<T>.getValue(thisRef: Any?, property: KProperty<*>): T = value

val generic: String by GenericHolder("generic")

class MemberPriorityHolder {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "member"
}

operator fun MemberPriorityHolder.getValue(thisRef: Any?, property: KProperty<*>): String = "wrong-extension"

val memberPriority: String by MemberPriorityHolder()

class EffectiveDelegate(val value: String)

operator fun EffectiveDelegate.getValue(thisRef: Any?, property: KProperty<*>): String = value
operator fun EffectiveDelegate.setValue(thisRef: Any?, property: KProperty<*>, value: String) { }

class DelegateFactory {
    operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): EffectiveDelegate =
        EffectiveDelegate("provided")
}

var provided: String by DelegateFactory()

fun main() {
    println(readOnly)
    mutable = "after"
    println(mutable)
    println(generic)
    println(memberPriority)
    println(provided)
    provided = "ignored"
}
