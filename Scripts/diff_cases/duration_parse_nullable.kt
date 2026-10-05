// KUU-1066: nullable parsers must carry the parsed value, not a legacy box address.
import kotlin.time.*
import kotlin.time.Duration.Companion.seconds

fun <T> identity(value: T): T = value

fun checkParsed(value: Duration?, expected: Duration) {
    println(value)
    println(value?.inWholeNanoseconds)
    println(value?.toString())
    println(value == expected)
    println((value ?: Duration.ZERO) + 1.seconds)
    println(value!!.compareTo(expected))
    println(identity(value) == expected)
    val erased: Any? = value
    println(erased is Duration)
    println(erased is Long)
    println((erased as Duration).inWholeNanoseconds == expected.inWholeNanoseconds)
    println(value.hashCode() == expected.hashCode())
}

fun main() {
    for (input in listOf("PT5S", "1h", "PT1H30M", "1.5s", "PT0S", "-1.5s", "Infinity")) {
        checkParsed(Duration.parseOrNull(input), Duration.parse(input))
    }
    for (input in listOf("PT5S", "PT1H30M", "PT1.5S", "PT0S", "-PT1.5S")) {
        checkParsed(Duration.parseIsoStringOrNull(input), Duration.parseIsoString(input))
    }
    val negativeInfinity = Duration.parseOrNull("-Infinity")
    println(negativeInfinity)
    println(negativeInfinity!! == Duration.parse("-Infinity"))
    println(negativeInfinity.inWholeNanoseconds)
    println(Duration.parseIsoStringOrNull("-PT999999999999999999999H"))
    val invalid = Duration.parseOrNull("bogus")
    println(invalid)
    println(invalid?.inWholeNanoseconds)
    println(invalid ?: 1.seconds)
    println(Duration.parseIsoStringOrNull("1h"))
    println(Duration.parse("PT1H30M"))
}
