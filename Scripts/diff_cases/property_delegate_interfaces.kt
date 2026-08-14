import kotlin.properties.PropertyDelegateProvider
import kotlin.properties.ReadOnlyProperty
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

class ReadOnlyBox<T>(private val value: T) : ReadOnlyProperty<Any?, T> {
    override operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value
}

class ReadWriteBox<T>(private var value: T) : ReadWriteProperty<Any?, T> {
    override operator fun getValue(thisRef: Any?, property: KProperty<*>): T = value

    override operator fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
        this.value = value
    }
}

class ReadOnlyProvider<T>(private val value: T) :
    PropertyDelegateProvider<Any?, ReadOnlyBox<T>> {
    override operator fun provideDelegate(thisRef: Any?, property: KProperty<*>): ReadOnlyBox<T> {
        println("provided ${property.name}")
        return ReadOnlyBox(value)
    }
}

fun acceptContravariantReceiver(delegate: ReadOnlyProperty<String, Any?>) {}

class Holder {
    val member by ReadOnlyProvider("member")
    var writable: String by ReadWriteBox("initial")
}

fun local(): String {
    val local by ReadOnlyProvider("local")
    return local
}

fun main() {
    val holder = Holder()
    println(holder.member)
    println(holder.writable)
    holder.writable = "updated"
    println(holder.writable)
    println(local())
    acceptContravariantReceiver(ReadOnlyBox("variance"))
}
