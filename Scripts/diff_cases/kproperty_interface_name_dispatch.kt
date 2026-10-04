// KCallable.name read through an interface-typed receiver. Compiler-tagged
// property references and runtime `property:` stubs answer through the
// runtime. The runtime itable shim used to return the raw String handle where
// the caller expected the flat String aggregate, which crashed (or printed
// garbage) on AArch64. User KCallable implementations cannot be expressed
// against the JVM KCallable surface, so they are covered by
// BundledStdlibExecutionTests+ReflectCallableInterfaceDispatch instead.
import kotlin.reflect.KCallable
import kotlin.reflect.KMutableProperty
import kotlin.reflect.KProperty

class Counter(var count: Int)

class Logger {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "read ${property.name}"
}

fun describe(callable: KCallable<*>): String = "callable ${callable.name}"

fun main() {
    val ref: KProperty<*> = Counter::count
    println(ref.name)
    println(Counter::count.name)

    val mutableRef: KMutableProperty<*> = Counter::count
    println(mutableRef.name)

    val bound: KProperty<*> = Counter(3)::count
    println(bound.name)

    val nullableRef: KProperty<*>? = Counter::count
    println(nullableRef?.name)

    println(describe(Counter::count))

    val callables: List<KCallable<*>> = listOf(Counter::count, Counter(1)::count)
    println(callables.map { it.name })

    val message: String by Logger()
    println(message)
}
