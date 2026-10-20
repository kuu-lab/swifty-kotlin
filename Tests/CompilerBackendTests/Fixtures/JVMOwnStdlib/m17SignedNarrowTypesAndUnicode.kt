fun read(c: Char, b: Byte, s: Short): Char { println(b); println(s); return c }
fun <T> same(x: T): T = x
fun main() {
    println(read('界', 127, -32768)); println('界'.code)
    println(255.toByte()); println(65535.toShort()); println(65535.toChar().code)
    val b: Byte = 100; val s: Short = 30000
    val number: Number = b; println(number.toByte()); println(number.toShort())
    println(b + b); println(s + s); println('Z' - 'A'); println('A' + 2)
    var byte: Byte = 127; byte++; println(byte); byte--; println(byte)
    var short: Short = 32767; short++; println(short)
    var char = '\uffff'; char++; println(char.code)
    val nullable: Char? = '界'; println(nullable); println(nullable!!.code)
    val empty: Char? = null; println(empty)
    val boxed: Any = b; println(boxed is Byte); println(same(s))
    for (c in 'x'..'z') { println(c) }
    val chars = charArrayOf('A', '\uffff'); chars[0] = '界'; println(chars[0]); println(chars[1].code)
    val bytes = ByteArray(2) { i -> (i + 127).toByte() }; println(bytes[1])
    val shorts = shortArrayOf(-32768, 32767); println(shorts[0]); println(shorts[1])
    println(Char(30028))
    try { Char(-1) } catch (e: IllegalArgumentException) { println(e.message) }
    try { Char(65536) } catch (e: IllegalArgumentException) { println(e.message) }
}
