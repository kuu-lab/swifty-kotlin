fun main() {
    var one = 1
    println(one shl 32)
    println(one shl 33)
    println(one shl 31)
    println(one shl 30)
    var neg = Int.MIN_VALUE
    println(neg shr 1)
    println(neg ushr 1)
    println(neg shr 32)
    println(neg ushr 32)
    println(one shl -1)
    println(1 shl 32)
    println(-1 ushr 1)
    var lone = 1L
    println(lone shl 64)
    println(lone shl 65)
    var lneg = Long.MIN_VALUE
    println(lneg shr 64)
}
