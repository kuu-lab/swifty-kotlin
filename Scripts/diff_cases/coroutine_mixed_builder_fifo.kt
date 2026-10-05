import kotlinx.coroutines.*

fun main() {
    runBlocking {
        launch {
            println("launch-1")
            yield()
            println("launch-2")
        }
        async {
            println("async-1")
            yield()
            println("async-2")
        }
        yield()
        println("parent")
    }

    runBlocking {
        repeat(4) { index ->
            if (index % 2 == 0) {
                launch {
                    println("launch $index first")
                    yield()
                    println("launch $index second")
                    yield()
                    println("launch $index third")
                }
            } else {
                async {
                    println("async $index first")
                    yield()
                    println("async $index second")
                    yield()
                    println("async $index third")
                    index
                }
            }
        }
        yield()
        println("round one")
        yield()
        println("round two")
    }

    runBlocking {
        async {
            println("outer async first")
            launch {
                println("nested launch first")
                yield()
                println("nested launch second")
            }
            async {
                println("nested async first")
                yield()
                println("nested async second")
            }
            yield()
            println("outer async second")
        }
        launch {
            println("sibling launch first")
            yield()
            println("sibling launch second")
        }
        yield()
        println("nested parent")
    }

    runBlocking {
        val scope = CoroutineScope(currentCoroutineContext())
        launch {
            println("launch before scope async")
            yield()
            println("launch resumed before scope async")
        }
        val task = scope.async {
            println("scope async first")
            yield()
            println("scope async second")
            42
        }
        yield()
        println("scope parent")
        println(task.await())
    }
}
