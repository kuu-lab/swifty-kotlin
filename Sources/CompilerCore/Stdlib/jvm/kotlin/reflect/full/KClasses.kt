@file:kotlin.jvm.JvmName("KClasses")
package kotlin.reflect.full
import kotlin.reflect.*
import kotlin.reflect.jvm.internal.*
import kotlin.jvm.internal.*
fun <T> getMemberProperties(type: KClass<T>): Collection<KProperty1<T, *>> {
    val result = mutableListOf<KProperty1<T, *>>()
    for (member in type.members) if (member is KProperty1<*, *>) result.add(member as KProperty1<T, *>)
    return result
}
fun getMemberFunctions(type: KClass<*>): Collection<KFunction<*>> {
    val result = mutableListOf<KFunction<*>>()
    for (member in type.members) if (member is KFunction<*> && !(member is KProperty<*>)) result.add(member)
    return result
}
fun <T: Any> createInstance(type: KClass<T>): T {
    var target: KFunction<T>? = null
    for (constructor in type.constructors) {
        var optional = true
        for (parameter in constructor.parameters) if (!parameter.isOptional) optional = false
        if (optional) {
            if (target != null) throw IllegalArgumentException("Class must have a single no-arg constructor")
            target = constructor
        }
    }
    if (target == null) throw IllegalArgumentException("Class must have a single no-arg constructor")
    return target!!.callBy(emptyMap())
}
