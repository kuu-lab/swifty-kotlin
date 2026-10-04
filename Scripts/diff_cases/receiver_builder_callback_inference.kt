class Builder<T> {
    fun use(block: () -> T) {
        println(block())
    }
}

fun <R> build(builder: Builder<R>.() -> Unit): R {
    val receiver = Builder<R>()
    receiver.builder()
    return 7 as R
}

class Clause<T>

class Choice<R> {
    fun <T> Clause<T>.onResult(block: (T) -> R) {
        println(block(3 as T))
    }
}

fun <R> choose(builder: Choice<R>.() -> Unit): R {
    val receiver = Choice<R>()
    receiver.builder()
    return 7 as R
}

fun main() {
    val result = build {
        use { 1 }
        use { 2 }
    }
    println(result + 1)
    val clause = Clause<Int>()
    val chosen = choose { clause.onResult { it + 1 } }
    println(chosen + 1)
}
