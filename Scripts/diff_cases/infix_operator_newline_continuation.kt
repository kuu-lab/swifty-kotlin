fun rev(x: Int): Int {
    return (x and -0x1000000 ushr 24) or
        (x and 0x00ff0000 ushr 8) or
        (x and 0x0000ff00 shl 8) or
        (x and 0x000000ff shl 24)
}

fun withAssignment(a: Int, b: Int): Int {
    var x = a
    x = x or
        b
    return x
}

fun main() {
    println(rev(0x01020304))
    println(withAssignment(1, 2))
}
