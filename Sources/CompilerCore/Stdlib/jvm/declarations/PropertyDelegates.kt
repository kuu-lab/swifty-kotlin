package kotlin.properties
interface ReadOnlyProperty<in T, out V> { operator fun getValue(thisRef: T, property: kotlin.reflect.KProperty<*>): V }
interface ReadWriteProperty<in T, V>: ReadOnlyProperty<T, V> {
    override operator fun getValue(thisRef: T, property: kotlin.reflect.KProperty<*>): V
    operator fun setValue(thisRef: T, property: kotlin.reflect.KProperty<*>, value: V)
}
object Delegates {
    fun <T: Any> notNull(): ReadWriteProperty<Any?, T> = null!!
    fun <T> observable(initialValue: T, onChange: (kotlin.reflect.KProperty<*>, T, T) -> Unit): ReadWriteProperty<Any?, T> = null!!
    fun <T> vetoable(initialValue: T, onChange: (kotlin.reflect.KProperty<*>, T, T) -> Boolean): ReadWriteProperty<Any?, T> = null!!
}