fun main() {
    val initialized = lazyOf(42)
    println(initialized.isInitialized())
    println(initialized.value)

    val deferred = lazy { 7 }
    println(deferred.isInitialized())
    println(deferred.value)
    println(deferred.value)
    println(deferred.isInitialized())

    val locked = lazy(null) { "locked" }
    println(locked.value)

    val mode = lazy(LazyThreadSafetyMode.NONE) { "none" }
    println(mode.value)
}
