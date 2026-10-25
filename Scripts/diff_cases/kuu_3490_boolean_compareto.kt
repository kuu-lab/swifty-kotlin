// KUU-3490: kotlin.Boolean implements Comparable<Boolean> on the JVM, so the
// member call and the relational operators must both resolve. Ordering is
// false < true.
fun main() {
    println(true.compareTo(false))
    println(false.compareTo(true))
    println(true.compareTo(true))
    println(false.compareTo(false))

    val t = true
    val f = false
    println(t.compareTo(f))
    println(f.compareTo(t))
    println(t > f)
    println(f < t)
    println(t >= t)
    println(f <= f)
    println(t < f)
    println(f > t)

    val c: Comparable<Boolean> = true
    println(c.compareTo(false))

    println(listOf(true, false, true, false).sorted())
    println(listOf(true, false).max())
    println(listOf(true, false).min())
    println(maxOf(true, false))
    println(minOf(true, false))
    println(listOf(true, false, true).sorted().joinToString(","))
}
