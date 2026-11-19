// DIFF_JVM
import kotlin.math.absoluteValue

fun intPercentage(value: Int, other: Int, percentage: Double): Boolean {
    val tolerance = other.times(percentage / 100).absoluteValue
    val range = (other - tolerance)..(other + tolerance)
    return value.toDouble() in range
}

fun longPercentage(value: Long, other: Long, percentage: Double): Boolean {
    val tolerance = other.times(percentage / 100).absoluteValue
    val range = (other - tolerance)..(other + tolerance)
    return value.toDouble() in range
}

fun main() {
    println("int.pct.89=${intPercentage(89, 100, 10.0)}")
    println("int.pct.90=${intPercentage(90, 100, 10.0)}")
    println("int.pct.111=${intPercentage(111, 100, 10.0)}")
    println("long.pct.89=${longPercentage(89L, 100L, 10.0)}")
    println("long.pct.90=${longPercentage(90L, 100L, 10.0)}")
    println("long.pct.111=${longPercentage(111L, 100L, 10.0)}")

    println("int.plus=${1.plus(2.0)}")
    println("int.minus=${1.minus(2.0)}")
    println("int.times=${1.times(2.0)}")
    println("int.div=${1.div(2.0)}")
    println("int.rem=${1.rem(2.0)}")
    println("long.plus=${1L.plus(2.0)}")
    println("long.minus=${1L.minus(2.0)}")
    println("long.times=${1L.times(2.0)}")
    println("long.div=${1L.div(2.0)}")
    println("long.rem=${1L.rem(2.0)}")
    println("int.timesFloat=${1.times(2.0f)}")
    println("long.timesFloat=${1L.times(2.0f)}")

    val byte: Byte = 3
    val short: Short = 4
    println("byte.times=${byte.times(1.5)}")
    println("short.times=${short.times(1.5)}")

    val nullableInt: Int? = 5
    val nullableLong: Long? = 6L
    val noInt: Int? = null
    println("nullable.int.times=${nullableInt?.times(1.5)}")
    println("nullable.long.times=${nullableLong?.times(1.5)}")
    println("null.int.times=${noInt?.times(1.5)}")
}
