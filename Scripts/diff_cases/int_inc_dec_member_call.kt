fun main() {
    println(Int.MAX_VALUE.inc())
    println(5.dec())
    println(5L.inc())
    println('a'.inc())
    val x = 10
    println(x.inc() + x.dec())
    var b2: Byte = 1
    println(b2.inc())
    val m: Int? = 4
    println(m?.inc())
}
