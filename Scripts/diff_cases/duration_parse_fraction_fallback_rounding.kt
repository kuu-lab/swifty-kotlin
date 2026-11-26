import kotlin.time.Duration

fun main() {
    println(Duration.parseOrNull("0.000000000008333333333333332m")?.inWholeNanoseconds)
    println(Duration.parseOrNull("0.000000000008333333333333333m")?.inWholeNanoseconds)
    println(Duration.parseOrNull("0.000000000008333333333333334m")?.inWholeNanoseconds)
}
