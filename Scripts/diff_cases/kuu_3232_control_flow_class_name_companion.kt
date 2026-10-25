// KUU-3232: a branch whose value is a bare class name denotes the companion
// object, so member lookup on the joined type must resolve companion members.
fun main() {
    val t = try { ULong } finally { }
    println(t.MAX_VALUE)
    println((try { ULong } finally { }).MIN_VALUE)

    val c = try { ULong } catch (e: Exception) { ULong }
    println(c.MAX_VALUE)

    val i = if (true) ULong else ULong
    println(i.MAX_VALUE)

    val w = when (1) { 1 -> ULong; else -> ULong }
    println(w.MIN_VALUE)

    println((null ?: ULong).MAX_VALUE)

    val d = UInt
    println(d.MAX_VALUE)
    val di = if (false) UInt else UInt
    println(di.MAX_VALUE)
}
