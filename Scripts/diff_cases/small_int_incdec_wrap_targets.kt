class Holder { var b: Byte = 127; var us: UShort = 65535u }
var g: Short = 32767

fun main() {
    val h = Holder()
    h.b++
    h.us++
    g++
    val ua: UByte = 200u
    println("${h.b} ${h.us} $g ${ua + ua}")
    var ch = 97.toChar()
    ch += 1
    println(ch)
    var chm = 0.toChar()
    chm -= 1
    println(chm.code)
}
