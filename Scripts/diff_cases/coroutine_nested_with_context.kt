import kotlinx.coroutines.*

fun main() {
    runBlocking {
        println(withContext(Dispatchers.Default) {
            withContext(Dispatchers.IO) { "nested" }
        })

        val prefix = "captured"
        val value = 40
        println(withContext(Dispatchers.Default) {
            withContext(Dispatchers.IO) {
                delay(1)
                "$prefix:${value + 2}"
            }
        })

        val number: Int = withContext(Dispatchers.Default) {
            withContext(Dispatchers.IO) {
                withContext(Dispatchers.Default) {
                    yield()
                    value + 3
                }
            }
        }
        println(number)
        println("resumed")

        try {
            withContext(Dispatchers.Default) {
                withContext(Dispatchers.IO) {
                    delay(1)
                    throw IllegalStateException("nested-boom")
                }
            }
        } catch (e: IllegalStateException) {
            println(e.message)
        }
    }
}
