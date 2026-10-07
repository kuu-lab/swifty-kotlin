fun main() {
    val z = 0
    try { println(5.floorDiv(0)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(5.mod(0)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(5L.floorDiv(0L)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(5L.mod(0L)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(5L.floorDiv(z)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(5L.mod(z)) } catch (e: ArithmeticException) { println(e.message) }
    val b: Byte = 5; val bz: Byte = 0
    try { println(b.floorDiv(bz)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(b.mod(bz)) } catch (e: ArithmeticException) { println(e.message) }
    val s: Short = 5; val sz: Short = 0
    try { println(s.floorDiv(sz)) } catch (e: ArithmeticException) { println(e.message) }
    try { println(s.mod(sz)) } catch (e: ArithmeticException) { println(e.message) }
    println((-7).floorDiv(2)); println((-7).mod(2)); println(7.mod(-2))
    println((-7L).floorDiv(2L)); println(Int.MIN_VALUE.floorDiv(-1)); println(Long.MIN_VALUE.mod(-1L))
    println((-7).toByte().mod(2.toByte())); println((-7).toShort().floorDiv(2.toShort()))
}
