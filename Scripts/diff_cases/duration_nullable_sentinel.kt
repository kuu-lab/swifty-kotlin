import kotlin.time.Duration

fun inspect(value: Duration?, expected: Duration) {
    println(value)
    println(value?.inWholeNanoseconds)
    println(value == expected)
    println(expected == value)
    println(value != expected)
    println(expected != value)
    println(value == null)
    println(value?.inWholeNanoseconds ?: 42L)
}

fun main() {
    val negative = Duration.parse("-Infinity")
    inspect(negative, negative)
    val positive = Duration.parse("Infinity")
    inspect(positive, positive)
    val finite = Duration.parse("1s")
    inspect(finite, finite)
    inspect(null, negative)
    inspect(finite, negative)
}
