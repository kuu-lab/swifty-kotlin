import kotlinx.coroutines.*

suspend fun invokeBody(receiver: String, body: suspend String.() -> Unit) {
    body(receiver)
}

suspend fun invokeValue(receiver: Int, body: suspend Int.(Int) -> String): String {
    return body(receiver, 3)
}

fun main() {
    val label = "v"
    val body: suspend String.() -> Unit = {
        println("$label:$this")
        delay(1)
        println("$label:$this")
    }
    val number = 7
    val value: suspend Int.(Int) -> String = { extra ->
        delay(1)
        "$label:$number:${this + extra}"
    }
    runBlocking {
        body("direct")
        invokeBody("forwarded", body)
        println(invokeValue(10, value))
        val plain: suspend String.() -> Unit = { println(this) }
        invokeBody("noncapturing", plain)
        val prefix = "literal"
        invokeBody("receiver") { println("$prefix:$this") }
    }
    println("done")
}
