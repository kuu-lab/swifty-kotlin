import kotlin.reflect.KMutableProperty1
import kotlin.reflect.KProperty
import kotlin.reflect.KProperty1

class Counter(var count: Int)

fun main() {
    // BUG (found via KSP-496): a property callable reference passed directly
    // into a generic call (e.g. `listOf(vararg elements: T)`) is type-checked
    // against the *unsubstituted* type parameter `T`, not the concrete
    // `KProperty1<Counter, Int>` the declared-`val` form gets. Sema used to
    // adopt that unsubstituted type verbatim as the reference's own static
    // type, which made KIR's KProperty wrapper lowering bail out (it only
    // recognizes a resolved `KProperty*` classType) and fall back to a legacy
    // bare-symbol path that crashes at runtime (calls the raw property
    // accessor with no receiver).
    val list: List<KProperty1<Counter, Int>> = listOf(Counter::count)
    println(list[0] is KProperty<*>)
    println(list[0].name)
    println(list[0].get(Counter(41)))

    val mutableList: List<KMutableProperty1<Counter, Int>> = listOf(Counter::count)
    val target = Counter(1)
    mutableList[0].set(target, 9)
    println(target.count)
    println(mutableList[0].get(target))
}
