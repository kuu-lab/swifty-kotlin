package golden.sema

// KSP-795: AutoCloseable.closeFinally preserves the primary exception and
// suppresses a close exception when use() closes a failing resource.

class ThrowingResource(private val throwOnClose: Boolean) : AutoCloseable {
    override fun close() {
        if (throwOnClose) throw IllegalStateException("close")
    }
}

fun useWithoutPrimary(): String {
    return try {
        ThrowingResource(true).use { "body" }
    } catch (e: Throwable) {
        e.message ?: "null"
    }
}

fun useWithPrimary(): Throwable {
    return try {
        ThrowingResource(true).use {
            throw IllegalStateException("primary")
        }
    } catch (e: Throwable) {
        e
    }
}

fun useWithNullReceiver(): String {
    val resource: AutoCloseable? = null
    return resource.use { if (it == null) "null" else "resource" }
}
