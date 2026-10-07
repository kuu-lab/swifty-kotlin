fun main() {
    // KSP-1530: stepping near ULong.MAX_VALUE must terminate instead of
    // wrapping back to small values.
    val nearMax = (ULong.MAX_VALUE - 4uL)..ULong.MAX_VALUE step 3
    println(nearMax.toList())
    println(((ULong.MAX_VALUE - 1uL)..ULong.MAX_VALUE step 3).toList())
    println((ULong.MAX_VALUE downTo (ULong.MAX_VALUE - 5uL) step 2).toList())
    println(nearMax.first)
    println(nearMax.last)
    println(nearMax.take(1))
    println(nearMax.drop(1))
    println(nearMax.chunked(1))
    println(nearMax.windowed(2, 1, true))
    for (value in (ULong.MAX_VALUE - 4uL)..ULong.MAX_VALUE step 3) print("$value ")
    println()
}
