fun <X> makeIt(x: X): X = x

class P<T : Any> {
    private val instance = makeIt<T?.() -> Int>({ 1 })
    fun read(value: T?): Int = instance(value)
}

fun main() {
    println(P<Int>().read(null))
    println(P<Int>().read(7))

    val nullableReceiver = makeIt<Int?.() -> Int> {
        if (this == null) 2 else 3
    }
    println(nullableReceiver(null))
    println(nullableReceiver(7))

    val withParameters = makeIt<Int?.(Int, Int) -> Int> { left, right ->
        if (this == null) left else right
    }
    println(withParameters(null, 4, 5))
    println(withParameters(7, 4, 5))

    val nullableReturn = makeIt<Int?.() -> Int?> { null }
    println(nullableReturn(null))

    val nullableFunction = makeIt<(Int?.() -> Int)?>(null)
    println(nullableFunction == null)

    val parenthesizedReceiver = makeIt<(Int)?.() -> Int> { 6 }
    println(parenthesizedReceiver(null))

    val genericReceiver = makeIt<kotlin.collections.List<Int>?.() -> Int> { 8 }
    println(genericReceiver(null))

    val nested = makeIt<List<Int?.() -> Int>>(listOf(nullableReceiver))
    println(nested[0](null))

    val nonNullableReceiver = makeIt<Int.() -> Int> { this }
    println(nonNullableReceiver(9))

    val value: Int? = null
    println(1 < (value?.toInt() ?: 2))
}
