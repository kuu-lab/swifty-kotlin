import kotlin.reflect.KMutableProperty
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty1

class Counter(var count: Int)

fun main() {
    // Devin Review finding on PR #5910: a property callable reference typed
    // against a broader (but concrete, non-generic) supertype like
    // `KProperty<*>`/`KMutableProperty<*>` -- as opposed to its own precise
    // `KProperty1<Owner, Value>` shape -- must still resolve to the precise
    // shape internally, or KIR's KProperty wrapper lowering can't build a
    // real wrapper object and falls back to a legacy path that crashes.
    val ref: KProperty<*> = Counter::count
    println(ref.name)
    println(ref is KProperty1<*, *>)

    val list: List<KProperty<*>> = listOf(Counter::count)
    println(list[0] is KProperty1<*, *>)

    val mutableRef: KMutableProperty<*> = Counter::count
    println(mutableRef.name)

    val any: Any = Counter::count
    println(any is KProperty1<*, *>)
}
