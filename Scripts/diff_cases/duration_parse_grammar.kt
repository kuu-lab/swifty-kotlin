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
}
