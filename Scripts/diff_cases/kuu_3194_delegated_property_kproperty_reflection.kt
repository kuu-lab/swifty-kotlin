import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KMutableProperty1
import kotlin.reflect.KMutableProperty2
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0
import kotlin.reflect.KProperty1
import kotlin.reflect.KProperty2

var captured0: KProperty<*>? = null
var captured1: KProperty<*>? = null
var captured2: KProperty<*>? = null

object Delegate0 {
    private var backing = "init0"
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String {
        captured0 = property
        return "g:${property.name}:${backing}"
    }
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        captured0 = property
        backing = value
    }
}

object Delegate1 {
    private var backing = "init1"
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String {
        captured1 = property
        return "g:${property.name}:${backing}"
    }
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        captured1 = property
        backing = value
    }
}

object Delegate2 {
    private var backing = "init2"
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String {
        captured2 = property
        return "g:${property.name}:${backing}"
    }
    operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        captured2 = property
        backing = value
    }
}

var topLevel: String by Delegate0

object O

object Holder {
    var member: String by Delegate1
    var O.ext: String by Delegate2
}

fun main() {
    topLevel = "a"
    println(topLevel)
    Holder.member = "b"
    println(Holder.member)
    with(Holder) { O.ext = "c"; println(O.ext) }

    val p0 = captured0 as KMutableProperty0<String>
    println("p0: name=${p0.name} get=${p0.get()} inv=${p0.invoke()} call=${p0.call()}")
    p0.set("z")
    println("p0 after set: ${p0.get()}")
    println("p0 shape: ${captured0 is KProperty0<*>} ${captured0 is KMutableProperty0<*>} ${captured0 is KProperty1<*, *>}")

    val p1 = captured1 as KMutableProperty1<Holder, String>
    println("p1: name=${p1.name} get=${p1.get(Holder)} inv=${p1.invoke(Holder)} call=${p1.call(Holder)}")
    p1.set(Holder, "y")
    println("p1 after set: ${p1.get(Holder)}")
    println("p1 shape: ${captured1 is KProperty1<*, *>} ${captured1 is KMutableProperty1<*, *>} ${captured1 is KProperty2<*, *, *>}")

    val p2 = captured2 as KMutableProperty2<Holder, O, String>
    println("p2: name=${p2.name} get=${p2.get(Holder, O)} inv=${p2.invoke(Holder, O)} call=${p2.call(Holder, O)}")
    p2.set(Holder, O, "x")
    println("p2 after set: ${p2.get(Holder, O)}")
    println("p2 shape: ${captured2 is KProperty2<*, *, *>} ${captured2 is KMutableProperty2<*, *, *>}")
}
