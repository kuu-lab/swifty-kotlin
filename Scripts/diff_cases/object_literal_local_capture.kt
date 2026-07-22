interface Greeter {
    fun greet(): String
}

interface Counter {
    fun increment(): Int
}

interface Box {
    fun value(): Int
}

interface Provider {
    fun provide(): Int
}

fun makeGreeter(name: String): Greeter {
    return object : Greeter {
        override fun greet(): String {
            return "Hello, " + name
        }
    }
}

fun makeCounter(start: Int): Counter {
    var count = start
    return object : Counter {
        override fun increment(): Int {
            count = count + 1
            return count
        }
    }
}

fun makeBox(): Box {
    val x = 100
    return object : Box {
        val x = 5
        override fun value(): Int {
            return x
        }
    }
}

fun makeProvider(block: () -> Int): Provider {
    return object : Provider {
        override fun provide(): Int {
            return block()
        }
    }
}

fun main() {
    val g = makeGreeter("World")
    println(g.greet())

    val c = makeCounter(10)
    println(c.increment())
    println(c.increment())
    println(c.increment())

    println(makeBox().value())

    val p = makeProvider { 42 }
    println(p.provide())
}
