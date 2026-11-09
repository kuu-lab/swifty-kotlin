// A member on a nullable implicit receiver is unsafe, but a same-named safe
// member on an outer receiver still outranks it, and Any members stay
// callable (KUU-4504). Pairs with
// kuu_4504_nullable_implicit_receiver_property_reject.kt.
class Outer { val length: Int = 99 }
class Box { var n: Int = 0 }
class Handler { val run: () -> Int = { 1 } }

fun outerShadow(s: String?): Int = with(Outer()) { with(s) { length } }
fun outerWrite(s: String?, b: Box): Int = with(b) { with(s) { n = 7; n } }
fun outerCallable(h: Handler?, o: Handler): Int = with(o) { with(h) { run() } }
fun smartCastOutside(s: String?): Int = if (s != null) with(s) { length } else 0
fun letInside(s: String?): Int? = s?.let { with(it) { length } }
fun viaToString(s: String?): String = with(s) { toString() }
fun viaHashCode(s: String?): Boolean = with(s) { hashCode() == hashCode() }
fun nonNullRead(b: Box): Int = with(b) { n }
fun nonNullWrite(b: Box): Int = with(b) { n = 5; n }
fun nonNullCallable(h: Handler): Int = with(h) { run() }

fun main() {
    println(outerShadow("abc"))
    println(outerWrite("x", Box()))
    println(outerCallable(null, Handler()))
    println(smartCastOutside("abcd"))
    println(smartCastOutside(null))
    println(letInside("ab"))
    println(letInside(null))
    println(viaToString(null))
    println(viaHashCode("x"))
    println(nonNullRead(Box()))
    println(nonNullWrite(Box()))
    println(nonNullCallable(Handler()))
}
