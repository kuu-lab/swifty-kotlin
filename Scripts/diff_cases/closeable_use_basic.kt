// KSP-611: Closeable / AutoCloseable / use are Kotlin source
// (Sources/CompilerCore/Stdlib/kotlin/io/Closeable.kt).
import java.io.Closeable

class Resource(val name: String) : Closeable {
    override fun close() {
        println("close $name")
    }
}

class AutoResource(val name: String) : AutoCloseable {
    override fun close() {
        println("auto close $name")
    }
}

class FailingResource(val name: String) : Closeable {
    override fun close() {
        throw IllegalStateException("close failed $name")
    }
}

fun useReturnsBlockValue(): String {
    return Resource("a").use { r -> "used ${r.name}" }
}

fun useClosesOnThrow() {
    try {
        Resource("b").use {
            throw RuntimeException("boom")
        }
    } catch (e: RuntimeException) {
        println("caught ${e.message}")
    }
}

fun useOnNullReceiver() {
    val r: Resource? = null
    println(r?.use { "unreachable" })
}

fun useOnAutoCloseable() {
    println(AutoResource("c").use { r -> "used ${r.name}" })
}

fun closeThroughInterfaceType() {
    val c: Closeable = Resource("d")
    c.close()
}

fun useRethrowsCloseFailure() {
    try {
        FailingResource("e").use { "ignored" }
    } catch (e: IllegalStateException) {
        println("caught ${e.message}")
    }
}

fun autoCloseableFactory() {
    val resource = AutoCloseable { println("close lambda") }
    resource.close()
}

fun main() {
    println(useReturnsBlockValue())
    useClosesOnThrow()
    useOnNullReceiver()
    useOnAutoCloseable()
    closeThroughInterfaceType()
    useRethrowsCloseFailure()
    autoCloseableFactory()
}
