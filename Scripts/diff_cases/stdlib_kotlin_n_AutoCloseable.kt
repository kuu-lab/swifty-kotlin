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

fun main() {
    println(useAutoCloseable())
    println(useFactory())
    closeThroughAutoCloseableInterface()
}
