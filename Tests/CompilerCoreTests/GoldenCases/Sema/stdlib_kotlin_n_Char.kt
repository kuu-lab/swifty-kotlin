package golden.sema

fun charFromInt() {
    val a = Char(65)
    val b = Char(0x03B2)
    val max = Char(0xFFFF)
    println(a.code)
    println(b.code)
    println(max.code)
}

fun charFromUShort() {
    val x = Char(0.toUShort())
    val y = Char(0x03B2.toUShort())
    val z = Char(0xFFFF.toUShort())
    println(x.code)
    println(y.code)
    println(z.code)
}

fun makeCharArray(): CharArray = charArrayOf('a', 'β', '\u0000')
