import kotlin.reflect.*
const val TOP = 6
object ConstObject { const val X = 7; val ordinary = 9 }
interface ConstInterface { companion object Named { const val X = 42; val ordinary = 43 } }
class ConstClass { companion object Named { const val X = 8; val ordinary = 10 } }
class Ordinary(val value: Int)
interface PrivateInterface { companion object Named { private const val SECRET = "private"; fun read() = SECRET } }
class PrivateClass { companion object { private const val SECRET = "private"; fun read() = SECRET } }
fun record(label: String, action: () -> Any?) {
    try { println(label + "=" + action()) }
    catch (failure: Throwable) { println(label + "=" + failure::class.simpleName) }
}
fun unbound(label: String, property: KCallable<*>, receiver: Any) {
    println(label + ".parameters=" + property.parameters.size)
    record(label + ".call0") { property.call() }
    record(label + ".call1") { property.call(receiver) }
    record(label + ".call2") { property.call(receiver, receiver) }
    record(label + ".by0") { property.callBy(emptyMap()) }
    record(label + ".by1") { property.callBy(mapOf(property.parameters[0] to receiver)) }
    record(label + ".get") { (property as KProperty1<Any, Any?>).get(receiver) }
}
fun bound(label: String, property: KProperty0<*>) {
    println(label + ".parameters=" + property.parameters.size)
    record(label + ".get") { property.get() }
    record(label + ".call0") { property.call() }
    record(label + ".call1") { property.call(1) }
    record(label + ".by0") { property.callBy(emptyMap()) }
}
fun member(owner: KClass<*>, name: String): KCallable<*> {
    for (property in owner.members) if (property.name == name) return property
    throw IllegalArgumentException("Missing test property")
}
fun main() {
    unbound("interface", member(ConstInterface.Named::class, "X"), ConstInterface.Named)
    unbound("object", member(ConstObject::class, "X"), ConstObject)
    unbound("class", member(ConstClass.Named::class, "X"), ConstClass.Named)
    unbound("ordinaryClass", member(Ordinary::class, "value"), Ordinary(11))
    unbound("ordinaryObject", member(ConstObject::class, "ordinary"), ConstObject)
    unbound("ordinaryInterface", member(ConstInterface.Named::class, "ordinary"), ConstInterface.Named)
    bound("boundInterface", ConstInterface::X)
    bound("boundObject", ConstObject::X)
    bound("boundClass", ConstClass::X)
    bound("top", ::TOP)
    println(PrivateInterface.read()); println(PrivateClass.read())
}
