import kotlin.time.measureTimedValue

fun main() {
    // Basic measureTimedValue with simple expression
    val result = measureTimedValue {
        "hello"
    }
    println(result.value)
    println(result.duration.inWholeMilliseconds >= 0)

    // measureTimedValue with integer computation
    val result2 = measureTimedValue {
        3 + 4
    }
    println(result2.value)
    println(result2.duration.inWholeMilliseconds >= 0)

    // KUU-4465: the top-level overload is generic, so TimedValue.value keeps
    // the lambda's type instead of widening to Any?.
    val result3 = measureTimedValue { "typed" }
    val typed: String = result3.value
    println(typed)
    println(measureTimedValue { 40 + 2 }.value + 0)
}
