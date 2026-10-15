val invert: (Boolean) -> Boolean = Boolean::not
val flip: (Boolean) -> Boolean = Boolean::flipExtension

fun Boolean.flipExtension(): Boolean = !this

fun box(): String {
    if ((Boolean::not).let { it(true) } != false) return "Fail 1"
    if ((Boolean::not).let { it(false) } != true) return "Fail 2"
    return if (!invert(true) && invert(false)) "OK" else "FAIL"
}

fun main() {
    println(box())
    println(flip(true))
    println(flip(false))
    println(true.not())
    println(!true)
}
