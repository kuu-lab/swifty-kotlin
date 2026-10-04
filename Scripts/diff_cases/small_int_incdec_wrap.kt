fun main() {
    var b: Byte = 127; b++
    var s: Short = -32768; s--
    var ub: UByte = 255u; ub++
    var us: UShort = 0u; us--
    println("$b $s $ub $us")
    var b2: Byte = -128; --b2; println(b2)
}
