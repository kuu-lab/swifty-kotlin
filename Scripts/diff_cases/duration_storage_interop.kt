import kotlin.time.*
import kotlin.time.Duration.Companion.nanoseconds

@OptIn(ExperimentalTime::class)
fun main() {
    val large = Long.MAX_VALUE.nanoseconds
    val text = large.toString()
    val parsed = Duration.parse(text)
    val nullable = Duration.parseOrNull(text)!!
    println(parsed == large)
    println(nullable == large)
    println(nullable.hashCode() == large.hashCode())
    println(nullable)
    println(Duration.parseIsoString(large.toIsoString()) == large)
    println(Duration.parseIsoStringOrNull((-large).toIsoString()) == -large)
    println(Duration.parse("9223372036854775807ns") == large)
    println(Duration.parse("9223372036854775807ms").isInfinite())
    val epoch = Instant.fromEpochSeconds(0L)
    val later = epoch + large
    println(later.epochSeconds)
    println(later.nanosecondsOfSecond)
    println(later - epoch == large)
    println(later - large == epoch)
    val twice = large * 2
    println((epoch + twice).epochSeconds)
    println((epoch + twice).nanosecondsOfSecond)
    println((epoch + twice) - epoch == twice)
}
