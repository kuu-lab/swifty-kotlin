// Regression for KUU-2463. The iterator fold comes from JetBrains Kotlin v2.3.10's
// realIteratorFoldl.kt; the remaining calls cover inference controls and boundaries.
tailrec fun <T, A> Iterator<T>.foldl(acc: A, foldFunction: (T, A) -> A): A =
    if (!hasNext()) acc else foldl(foldFunction(next(), acc), foldFunction)

fun <A> fold(seed: A, step: (Int, A) -> A): A = step(1, seed)
fun <T> choose(seed: T?, step: (T) -> T?): T? = seed

fun <A> overloaded(seed: A, step: (Int, A) -> A): A = step(1, seed)
fun overloaded(seed: Int, step: (Int, String) -> String): String = step(1, "")

fun box(): String {
    val sum = (1..1000000).iterator().foldl(0) { element: Int, accumulator: Long ->
        accumulator + element
    }
    return if (sum == 500000500000) "OK" else "FAIL: $sum"
}

fun minimum(): String = fold(0) { element: Int, accumulator: Long -> accumulator + element }.toString()

fun positiveControls(): String {
    val explicitTypeArgument = fold<Long>(0) { element: Int, accumulator: Long -> accumulator + element }
    val longSeed = fold(0L) { element: Int, accumulator: Long -> accumulator + element }
    val intLambda = fold(0) { element: Int, accumulator: Int -> accumulator + element }
    return "$explicitTypeArgument/$longSeed/$intLambda"
}

fun nullableSeed(): String = choose(null) { value: Long -> value }.toString()

fun overloadedControl(): String = overloaded(0) { element: Int, accumulator: Long ->
    accumulator + element
}.toString()

fun main() {
    println(box())
    println(minimum())
    println(positiveControls())
    println(nullableSeed())
    println(overloadedControl())
}
