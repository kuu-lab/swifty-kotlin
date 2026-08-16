fun main() {
    println(Char(65).code)
    println(Char(0).code)
    println(Char(0x03B2).code)
    println(Char(0xFFFF).code)

    println(Char(65.toUShort()).code)
    println(Char(0.toUShort()).code)
    println(Char(0x03B2.toUShort()).code)
    println(Char(0xFFFF.toUShort()).code)
}
