import kotlin.math.*

fun main() {
    // abs(Long)
    val absLong: Long = abs(-42L)
    println(absLong)
    val absLongZero: Long = abs(0L)
    println(absLongZero)

    // truncate(Double)
    val truncD: Double = truncate(3.7)
    println(truncD)
    val truncDNeg: Double = truncate(-3.7)
    println(truncDNeg)

    // truncate(Float)
    val truncF: Float = truncate(3.7f)
    println(truncF)
    val truncFNeg: Float = truncate(-3.7f)
    println(truncFNeg)

    // Double.IEEErem(Double)
    val remD: Double = 7.0.IEEErem(2.5)
    println(remD)

    // Float.IEEErem(Float)
    val remF: Float = 7.0f.IEEErem(2.5f)
    println(remF)

    // Double.withSign(Double)
    val ws1: Double = 3.0.withSign(-1.0)
    println(ws1)
    val ws2: Double = (-3.0).withSign(1.0)
    println(ws2)

    // Float.withSign(Float)
    val wsF: Float = 3.0f.withSign(-1.0f)
    println(wsF)

    // Double.withSign(Int)
    val wsI: Double = 3.0.withSign(-1)
    println(wsI)

    // Double.nextTowards(Double)
    val nt: Double = 1.0.nextTowards(2.0)
    println(nt)
}
