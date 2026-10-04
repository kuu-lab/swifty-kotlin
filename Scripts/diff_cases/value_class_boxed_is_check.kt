@JvmInline
value class Meters(val value: Int)

@JvmInline
value class Seconds(val value: Int)

fun boxMeters(m: Meters): Any = m
fun isMeters(x: Any): Boolean = x is Meters
fun isSeconds(x: Any): Boolean = x is Seconds

val globalBoxedMeters: Any = Meters(9)

fun main() {
    val boxed = boxMeters(Meters(5))
    println(boxed is Meters)
    println(boxed is Seconds)
    println(boxed is Int)
    println(isMeters(Meters(7)))
    println(isSeconds(Meters(7)))

    val list: List<Any> = listOf(Meters(1), Meters(2), Seconds(3))
    var metersCount = 0
    for (item in list) {
        if (item is Meters) metersCount++
    }
    println(metersCount)

    println(globalBoxedMeters is Meters)
    println(globalBoxedMeters is Seconds)
}
