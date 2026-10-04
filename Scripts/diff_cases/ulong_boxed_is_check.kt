fun check(x: Any?) {
    println(x is ULong)
    println(x is Long)
    if (x is ULong) {
        println("cast ok: $x")
    }
}

fun main() {
    check(17663719463477156090uL)
    check(5L)
}
