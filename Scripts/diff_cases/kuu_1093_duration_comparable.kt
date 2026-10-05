// KUU-1093: bundled kotlin.time.Duration declares `Comparable<Duration>` with
// a member `compareTo` override (previously an extension operator, which left
// every generic `T : Comparable<T>` context unsatisfiable).
import kotlin.time.Duration
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

fun main() {
    println(1.days < 2.days)
    println(2.days <= 2.days)
    println(3.hours > 2.hours)
    println(1.days.compareTo(2.hours))
    val d: Comparable<Duration> = 1.days
    println(d.compareTo(2.hours))
    println(1.days is Comparable<*>)
    println(listOf(1.days, 2.hours, 30.minutes, 5.seconds).sorted())
    println(listOf(1.days, 2.hours, 30.minutes).sortedDescending())
    val m = mutableListOf(2.hours, 1.days, 30.minutes)
    m.sort()
    println(m)
    m.sortDescending()
    println(m)
    val l = listOf(1.days, 2.hours, 30.minutes)
    println(l.max())
    println(l.min())
    println(l.maxOrNull())
    println(l.minOrNull())
    println(emptyList<Duration>().maxOrNull())
    println(maxOf(1.days, 2.hours))
    println(minOf(1.days, 2.hours))
    println(maxOf(1.days, 2.hours, 30.minutes))
    println(listOf("bbb", "a", "cc").maxOf { it.length.days })
    println(listOf("bbb", "a", "cc").maxByOrNull { it.length.days })
    println(compareValues(1.days, 2.hours))
    println(compareValues(1.days, null))
    println(compareValues(null, null))
    println(l.sortedWith(naturalOrder()))
    println(l.sortedWith(reverseOrder()))
    println(listOf(1.days, null, 2.hours).sortedWith(nullsFirst(naturalOrder())))
    println(listOf("bb", "ccc", "a").sortedBy { it.length.days })
    println(listOf("bb", "ccc", "a").sortedWith(compareBy { it.length.days }))
    println(listOf("bb", "ccc", "a").maxOfWith(naturalOrder()) { it.length.days })
    println(listOf(24.hours, 1.days, 1440.minutes).sorted().distinct().size)
    println(1.days == 24.hours)
    println(1.days.compareTo(24.hours))
}
