import kotlin.properties.Delegates
import kotlin.reflect.KProperty
interface Extensions { fun Int.doubled(): Int }
class Implementation: Extensions { override fun Int.doubled(): Int = this * 2 }
class Forward(delegate: Extensions): Extensions by delegate { fun run(): Int = 21.doubled() }
class Delegate(val value: Int)
class Owner {
    operator fun Delegate.getValue(thisRef: Owner, p: KProperty<*>): Int = value
    val number: Int by Delegate(42)
}
var computed: Int = 1
    get() = field + 1
    private set(value) { field += value }
fun main() {
    println(Forward(Implementation()).run()); println(Owner().number)
    var observed: Int by Delegates.observable(onChange = { p, old, new -> println(new) }, initialValue = 1)
    observed = 2; println(observed)
    var limited: Int by Delegates.vetoable(onChange = { p, old, new -> new > old }, initialValue = 10)
    limited = 5; println(limited)
    computed = 3; println(computed)
}
