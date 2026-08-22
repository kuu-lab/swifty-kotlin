package golden.sema

// KSP-721: kotlin.AutoCloseable interface and factory are source-backed.

class MyAutoResource : AutoCloseable {
    override fun close() {
        println("closed")
    }
}

fun autoCloseableFactory(): AutoCloseable {
    return AutoCloseable {
        println("factory closed")
    }
}

fun useAutoCloseable(): String {
    val r = MyAutoResource()
    return r.use { "used" }
}

fun useFactory(): String {
    val r = autoCloseableFactory()
    return r.use { "factory-used" }
}
