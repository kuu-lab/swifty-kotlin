// KUU-4030: a `var` property obtained through memberProperties /
// declaredMemberProperties reflects as KMutablePropertyN (a `val` as
// KPropertyN), like the JVM's kotlin-reflect handles.
import kotlin.reflect.full.*
import kotlin.reflect.*

class C(val c1: Int, var c2: String)

fun main() {
    val p = C::class.memberProperties.first { it.name == "c2" }
    println(p is KMutableProperty<*>)
    println(p is KMutableProperty1<*, *>)
    println(p is KProperty1<*, *>)
    println(p is KProperty<*>)
    val v = C::class.memberProperties.first { it.name == "c1" }
    println(v is KMutableProperty<*>)
    println(v is KMutableProperty1<*, *>)
    println(v is KProperty1<*, *>)
    println(v is KProperty<*>)
    val d = C::class.declaredMemberProperties.first { it.name == "c2" }
    println(d is KMutableProperty<*>)
    println(d is KMutableProperty1<*, *>)
    println((p as? KMutableProperty<*>) != null)
    println((v as? KMutableProperty<*>) == null)
    println(C::c2 is KMutableProperty1<*, *>)
    println(C::c1 !is KMutableProperty<*>)
}
