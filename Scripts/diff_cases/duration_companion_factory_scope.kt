import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds as sec

fun main() {
    println(1.sec)
    println(2L.sec)
    println(1.5.sec)
    Duration.run {
        println(1.nanoseconds)
        println(2L.microseconds)
        println(1.5.milliseconds)
        println(1.seconds)
        println(2L.minutes)
        println(1.5.hours)
        println(1.days)
    }
    with(Duration) {
        println(2L.nanoseconds)
        println(1.5.microseconds)
        println(1.milliseconds)
        println(2L.seconds)
        println(1.5.minutes)
        println(1.hours)
        println(2L.days)
    }
    Duration.apply {
        println(1.5.nanoseconds)
        println(1.microseconds)
        println(2L.milliseconds)
        println(1.5.seconds)
        println(1.minutes)
        println(2L.hours)
        println(1.5.days)
    }
}
