fun main() {
    val initialized = lazyOf(42)
    println(initialized.isInitialized())
    println(initialized.value)

    val deferred = lazy { 7 }
    println(deferred.isInitialized())
    println(deferred.value)
    println(deferred.isInitialized())
}
