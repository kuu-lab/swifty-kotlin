package kotlin.properties
interface ReadOnlyProperty<in T, out V> { operator fun getValue(thisRef: T, property: kotlin.reflect.KProperty<*>): V }
interface ReadWriteProperty<in T, V>: ReadOnlyProperty<T, V> {
    override operator fun getValue(thisRef: T, property: kotlin.reflect.KProperty<*>): V
    operator fun setValue(thisRef: T, property: kotlin.reflect.KProperty<*>, value: V)
}
private class NotNullProperty<T: Any>: ReadWriteProperty<Any?, T> {
    private var stored: T? = null
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = stored ?: throw IllegalStateException("Property ${property.name} should be initialized before get.")
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) { stored = value }
}
private class CallbackObservableProperty<T>(private var stored: T, private val callback: (kotlin.reflect.KProperty<*>, T, T) -> Unit): ReadWriteProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = stored
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) {
        val old = stored
        stored = value
        callback(property, old, value)
    }
}
private class VetoableProperty<T>(private var stored: T, private val callback: (kotlin.reflect.KProperty<*>, T, T) -> Boolean): ReadWriteProperty<Any?, T> {
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = stored
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: T) {
        if (callback(property, stored, value)) stored = value
    }
}
object Delegates {
    fun <T: Any> notNull(): ReadWriteProperty<Any?, T> = NotNullProperty<T>()
    fun <T> observable(initialValue: T, onChange: (kotlin.reflect.KProperty<*>, T, T) -> Unit): ReadWriteProperty<Any?, T> = CallbackObservableProperty(initialValue, onChange)
    fun <T> vetoable(initialValue: T, onChange: (kotlin.reflect.KProperty<*>, T, T) -> Boolean): ReadWriteProperty<Any?, T> = VetoableProperty(initialValue, onChange)
}

abstract class ObservableProperty<V>(initialValue: V): ReadWriteProperty<Any?, V> {
    private var storedValue = initialValue
    protected open fun beforeChange(property: kotlin.reflect.KProperty<*>, oldValue: V, newValue: V): Boolean = true
    protected open fun afterChange(property: kotlin.reflect.KProperty<*>, oldValue: V, newValue: V) {}
    override fun getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): V = storedValue
    override fun setValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>, value: V) {
        val old = storedValue
        if (!beforeChange(property, old, value)) return
        storedValue = value
        afterChange(property, old, value)
    }
}
