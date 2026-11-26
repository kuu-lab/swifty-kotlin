// DIFF_JVM
import kotlin.time.Duration

fun main() {
    println(Duration.parse("1h30m"))
    println(Duration.parseOrNull("1e3s") == null)
    println(Duration.parseOrNull("1.s") == null)
    println(Duration.parseOrNull(".5s") == null)
    println(Duration.parseOrNull(" 1h 30m ") == null)
    println(Duration.parseIsoStringOrNull(" PT1H ") == null)
    println(Duration.parseIsoString("PT-1H"))
    println(Duration.parse("0.5s"))
    println(Duration.parse("-(1h 30m)"))
    println(Duration.parseOrNull("+1h 30m") == null)
    println(Duration.parseOrNull("30m 1h") == null)
    println(Duration.parse("infinity"))
    println(Duration.parseOrNull("0.0000000075s")?.inWholeNanoseconds)
    println(Duration.parseIsoStringOrNull("PT0.0000000075S")?.inWholeNanoseconds)
    println(Duration.parseIsoStringOrNull("PT99999999999999999999H-99999999999999999999M") == null)
    println(Duration.parseIsoStringOrNull("PT99999999999999999999H99999999999999999999M"))
    println(Duration.parseOrNull("ınfinity"))
    println(Duration.parseOrNull("İnfinity"))
}
