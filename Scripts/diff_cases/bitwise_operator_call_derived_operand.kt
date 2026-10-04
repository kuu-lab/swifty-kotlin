// DEBT-KIR-004 regression: bitwise operators must not drop an operand that
// was bound (via a `val`) to the result of a preceding function call,
// regardless of which side of the operator it appears on.
fun main() {
    val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    val source = "HelloWorld"

    var orAcc = 0
    var andAcc = -1
    var xorAcc = 0
    var shlAcc = 1
    var shrAcc = 0x7FFFFFFF
    var ushrAcc = -1
    var i = 0
    while (i < source.length) {
        val c = source[i]
        val value = alphabet.indexOf(c)
        orAcc = (orAcc shl 1) or value
        andAcc = andAcc and (value or 0x3F)
        xorAcc = (xorAcc shl 1) xor value
        shlAcc = 1 shl (value and 7)
        shrAcc = 0x7FFFFFFF shr (value and 7)
        ushrAcc = -1 ushr (value and 7)
        i += 1
    }
    println(orAcc)
    println(andAcc)
    println(xorAcc)
    println(shlAcc)
    println(shrAcc)
    println(ushrAcc)

    var orAccL = 0L
    var andAccL = -1L
    var xorAccL = 0L
    i = 0
    while (i < source.length) {
        val c = source[i]
        val value = alphabet.indexOf(c).toLong()
        orAccL = (orAccL shl 1) or value
        andAccL = andAccL and (value or 0x3FL)
        xorAccL = (xorAccL shl 1) xor value
        i += 1
    }
    println(orAccL)
    println(andAccL)
    println(xorAccL)

    val v = alphabet.indexOf('Z')
    println(0 or v)
    println(v or 0)
    println(63 and v)
    println(v and 63)
    println(0 xor v)
    println(v xor 0)
}
