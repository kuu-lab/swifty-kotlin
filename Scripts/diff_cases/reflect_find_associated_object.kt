// CANDIDATE-ONLY: main only prints "ok"; this does not exercise findAssociatedObject lookup semantics.
import kotlin.reflect.ExperimentalAssociatedObjects
import kotlin.reflect.KClass
import kotlin.reflect.findAssociatedObject

@OptIn(ExperimentalAssociatedObjects::class)
annotation class Binding

object BindingInstance

@OptIn(ExperimentalAssociatedObjects::class)
@Binding
class Bound

@OptIn(ExperimentalAssociatedObjects::class)
fun <T : Any> find(kclass: KClass<T>): Any? = kclass.findAssociatedObject<Binding>()

fun main() {
    println("ok")
}
