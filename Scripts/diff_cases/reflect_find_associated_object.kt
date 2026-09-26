// SKIP-DIFF (DEBT-DIFF-001): kswiftc resolves kotlin.reflect.findAssociatedObject via the
// synthetic __kk_kclass_find_associated_object link, which has no Runtime implementation yet,
// so the kswiftc side cannot link or run this case.
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
