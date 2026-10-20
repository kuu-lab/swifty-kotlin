import kotlin.reflect.KProperty
import kotlin.properties.ReadWriteProperty
interface Cell<T> { var value: T; fun exchange(next: T): T; fun <R> identity(value: R): R = value }
class IntCell(override var value: Int): Cell<Int> {
    override fun exchange(next: Int): Int { val old = value; value = next; return old }
}
class Relay(delegate: Cell<Int>): Cell<Int> by delegate
class Standard: ReadWriteProperty<Any?, Int> {
    private var stored = 4
    override operator fun getValue(thisRef: Any?, property: KProperty<*>): Int = stored
    override operator fun setValue(thisRef: Any?, property: KProperty<*>, value: Int) { stored = value }
}
class ExtensionDelegate<T>(var stored: T)
operator fun <T> ExtensionDelegate<T>.getValue(thisRef: Any?, property: KProperty<*>): T = stored
operator fun <T> ExtensionDelegate<T>.setValue(thisRef: Any?, property: KProperty<*>, value: T) { stored = value }
class Holder { var member: Int by Standard() }
fun main() {
    val relay = Relay(IntCell(10))
    val cell: Cell<Int> = relay
    println(cell.exchange(20)); println(relay.value); relay.value = 30; println(cell.value)
    println(relay.identity("generic"))
    val h = Holder(); println(h.member); h.member = 8; println(h.member)
    var x: Int by ExtensionDelegate(3)
    x += 5; println(x)
}
