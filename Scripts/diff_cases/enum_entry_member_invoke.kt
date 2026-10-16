enum class A {
    ONE, TWO;

    operator fun invoke(value: Int): Int = value
    operator fun invoke(value: String): String = value
    fun echo(value: Int): Int = value
}

enum class Overridden {
    ONE { override operator fun invoke(value: Int): Int = value + 1 },
    TWO;

    open operator fun invoke(value: Int): Int = value
}

class Callable {
    operator fun invoke(value: Int): Int = value
}

fun box(): String {
    val callable = Callable()
    return if (A.ONE(42) == 42
        && A.ONE("OK") == "OK"
        && A.TWO.echo(42) == 42
        && callable(42) == 42
        && Overridden.ONE(41) == 42
    ) "OK" else "FAIL"
}

fun main() {
    println(box())
}
