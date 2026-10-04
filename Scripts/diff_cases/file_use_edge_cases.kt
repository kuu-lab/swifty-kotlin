import java.io.Closeable

class TraceResource(private val name: String) : Closeable {
    override fun close() {
        println("close:$name")
    }
}

fun main() {
    val result = TraceResource("ok").use {
        println("use:ok")
        "done"
    }
    println(result)

    try {
        TraceResource("fail").use {
            println("use:fail")
            error("boom")
        }
    } catch (e: Throwable) {
        println("caught")
    }

    val nullable: TraceResource? = null
    println(nullable?.use { "nope" })
}
