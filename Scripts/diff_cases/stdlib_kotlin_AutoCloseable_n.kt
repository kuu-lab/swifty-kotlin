// KSP-795: AutoCloseable.use must preserve a block exception and suppress a
// close exception without changing the nullable receiver or close-only paths.

class ThrowingResource(private val throwOnClose: Boolean) : AutoCloseable {
    override fun close() {
        if (throwOnClose) throw IllegalStateException("close")
    }
}

fun main() {
    try {
        ThrowingResource(false).use {
            throw IllegalStateException("primary-only")
        }
    } catch (e: Throwable) {
        println(e.message)
        println(e.suppressedExceptions.size)
    }

    try {
        ThrowingResource(true).use {
            throw IllegalStateException("primary")
        }
    } catch (e: Throwable) {
        println(e.message)
        println(e.suppressedExceptions.size)
        println(e.suppressedExceptions[0].message)
    }

    try {
        ThrowingResource(true).use { "body" }
    } catch (e: Throwable) {
        println(e.message)
        println(e.suppressedExceptions.size)
    }

    val resource: AutoCloseable? = null
    resource.use { println(if (it == null) "null" else "resource") }
}
