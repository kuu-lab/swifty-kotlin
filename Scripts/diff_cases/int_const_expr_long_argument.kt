// Int constant expressions built from literals are accepted where Long is expected (KUU-2779).
class L(val a: Long)

class Lcg(val a: Long, val c: Long, val m: Long, val shift: Long)

fun f(x: Long) = x

fun sum(a: Long, b: Long) = a + b

fun main() {
    println(L(1 shl 31).a)
    println(L(42).a)
    println(f(1 shl 16))
    println(f(2 * 3 + 1))
    println(f(-(1 shl 3)))
    println(f(-(1 shl 31)))
    println(f((1 shl 4) or 3))
    println(f(7 and 3 xor 1))
    println(f(1 shl 31 ushr 4))
    println(sum(1 shl 31, 1 shl 16))
    val lcg = Lcg(214013, 2531011, 1 shl 31, 1 shl 16)
    println(lcg.m + lcg.shift)
    val x: Long = 1 shl 31
    println(x)
}
