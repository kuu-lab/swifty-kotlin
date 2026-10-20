package kotlin
interface Lazy<out T> { val value: T; fun isInitialized(): Boolean }
enum class LazyThreadSafetyMode { SYNCHRONIZED, PUBLICATION, NONE }
