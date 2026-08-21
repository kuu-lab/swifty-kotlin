fun main() {
    val initialized = lazyOf(42)
    println(initialized.isInitialized())
    println(initialized.value)

    val deferred = lazy { 7 }
    println(deferred.isInitialized())
    println(deferred.value)
    println(deferred.isInitialized())

    val custom: Lazy<Int> = CustomLazy(99)
    println(custom.isInitialized())
    println(custom.value)
    println(custom.isInitialized())
}

class CustomLazy<T>(private var v: T?) : Lazy<T> {
    override val value: T
        get() = v ?: throw IllegalStateException("not initialized")
    override fun isInitialized(): Boolean = v != null
}
