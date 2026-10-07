import kotlinx.coroutines.*

fun main() {
    runBlocking {
        val child = launch {
            println("child-1")
            yield()
            println("child-2")
        }
        yield()
        println("parent")
    }
    println("runBlocking returned")

    runBlocking {
        launch {
            println("first-1")
            yield()
            println("first-2")
            yield()
            println("first-3")
            launch {
                yield()
                println("grandchild")
            }
        }
        launch {
            println("second-1")
            yield()
            println("second-2")
        }
        yield()
        println("multiple parent")
    }
    println("multiple runBlocking returned")

    runBlocking {
        async {
            println("async-1")
            yield()
            println("async-2")
        }
        yield()
        println("async parent")
    }
    println("async runBlocking returned")
}
