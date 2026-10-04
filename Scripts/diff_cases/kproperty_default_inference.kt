// KSP-496 follow-up: a property callable reference (`Type::property` /
// `instance::property`) without an explicit expected type must still infer
// to a real KProperty0/KProperty1, not the property's own value type.
import kotlin.reflect.KProperty1

class Sample(val v: Int)

fun main() {
    val unbound = Sample::v
    println("unbound is KProperty1: ${unbound is KProperty1<*, *>}")
    println("unbound name: ${unbound.name}")

    val sample = Sample(42)
    val bound = sample::v
    println("bound name: ${bound.name}")
    println("bound get: ${bound.get()}")
}
