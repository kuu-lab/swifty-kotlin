@JvmInline
value class Meter(val value: Int)

inline class LegacyCount(val value: Int)

fun report(meter: Meter, count: LegacyCount): Int = meter.value + count.value

fun main() {
    println(report(Meter(42), LegacyCount(7)))
}
