package golden.sema

fun main() {
    val x: UInt = 42u
    val y: ULong = 42uL
    val a = x.toInt()
    val b = x.toUInt()
    val c = x.toLong()
    val d = x.toULong()
    val e = y.toInt()
    val h = (1uL..7uL).toULongArray()
    val f = 100u / 3u
    val g = 100u % 3u
    val i = 255u and 15u
    val j = 240u or 15u
    val k = 255u xor 15u
    val l = 255u shl 2
    val m = 240u shr 2
    // toFloat / toDouble from unsigned types
    val nf = x.toFloat()
    val nd = x.toDouble()
    val pf = y.toFloat()
    val pd = y.toDouble()
    // UByte / UShort cross-conversions
    val ub = 200u.toUByte()
    val us = 1000u.toUShort()
    val ubf = ub.toFloat()
    val ubd = ub.toDouble()
    val usf = us.toFloat()
    val usd = us.toDouble()
    val ubToUs = ub.toUShort()
    val usToBub = us.toUByte()
    val ubId = ub.toUByte()
    val usId = us.toUShort()
    println(a)
    println(b)
    println(c)
    println(d)
    println(e)
    println(h)
    println(f)
    println(g)
    println(i)
    println(j)
    println(k)
    println(l)
    println(m)
    println(nf)
    println(nd)
    println(pf)
    println(pd)
    println(ubf)
    println(ubd)
    println(usf)
    println(usd)
    println(ubToUs)
    println(usToBub)
    println(ubId)
    println(usId)
}
