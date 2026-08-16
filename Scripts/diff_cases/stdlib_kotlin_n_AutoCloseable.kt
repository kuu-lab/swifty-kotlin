// KSP-721: kotlin.AutoCloseable interface and factory are source-backed.
import kotlin.AutoCloseable

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
    return MyAutoResource().use { "used" }
}

fun useFactory(): String {
    return autoCloseableFactory().use { "factory-used" }
}

fun closeThroughAutoCloseableInterface() {
    val c: AutoCloseable = MyAutoResource()
    c.close()
}

class GenericResource : AutoCloseable {
    var closed = false
    fun doIt() = "generic"
    fun label() = "label"
    override fun close() { closed = true }
}

fun <T : AutoCloseable> useIt(t: T, block: (T) -> String): String = t.use { block(it) }

fun <T : AutoCloseable> useItWithMessage(t: T, prefix: String, block: (T, String) -> String): String =
    t.use { block(it, prefix) }

fun <T : AutoCloseable> useItNoCapture(t: T): String = t.use { "nocapture" }

fun main() {
    println(useAutoCloseable())
    println(useFactory())
    closeThroughAutoCloseableInterface()
    val gr = GenericResource()
    println(useIt(gr) { it.doIt() })
    println(gr.closed)
    println(useItWithMessage(gr, "msg") { it, p -> "$p:${it.label()}" })
    println(gr.closed)
    println(useItNoCapture(gr))
    println(gr.closed)
}
