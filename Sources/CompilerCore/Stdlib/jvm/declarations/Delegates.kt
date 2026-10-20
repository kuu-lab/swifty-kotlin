package kotlin
interface Lazy<out T> { val value: T; fun isInitialized(): Boolean }
enum class LazyThreadSafetyMode { SYNCHRONIZED, PUBLICATION, NONE }
fun <T> lazy(initializer: () -> T): Lazy<T> = null!!
fun <T> lazy(mode: LazyThreadSafetyMode, initializer: () -> T): Lazy<T> = null!!
fun <T> lazy(lock: Any?, initializer: () -> T): Lazy<T> = null!!
operator fun <T> Lazy<T>.getValue(thisRef: Any?, property: kotlin.reflect.KProperty<*>): T = value
