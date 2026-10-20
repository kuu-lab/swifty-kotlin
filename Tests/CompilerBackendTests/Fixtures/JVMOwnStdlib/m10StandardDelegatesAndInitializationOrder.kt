import kotlin.properties.Delegates
import kotlin.reflect.KProperty
fun mark(n: Int): Int { println(n); return n }
interface I { fun read(): Int }
class Impl(val n: Int): I { override fun read(): Int = n }
open class Base { init { println(1) } }
class Wrapper: Base(), I by Impl(mark(2)) {
    val value: Int by lazy { mark(5) }
    val initial = mark(3)
    init { println(4) }
}
fun main() {
    val wrapper = Wrapper(); println(wrapper.read()); println(wrapper.value); println(wrapper.value)
    var observed: Int by Delegates.observable(1) { p, old, new -> println(p.name); println(old); println(new) }
    observed = 2; println(observed)
    var accepted: Int by Delegates.vetoable(10) { p, old, new -> new > old }
    accepted = 5; println(accepted); accepted = 20; println(accepted)
    var required: String by Delegates.notNull()
    try { println(required) } catch (e: IllegalStateException) { println("missing") }
    required = "ready"; println(required)
}
