// DIFF_JVM
// KUU-4080 / KUU-4083: the `:` introducing a return type or declared type may
// start on the line after an extension-receiver signature.
class Box<A>(val a: A)

fun <T> Box<T>.asIs()
    : Box<T> {
    return this
}

fun Box<Int>.plusOne()
    : Box<Int> = Box(this.a + 1)

val Box<Int>.intValue
    : Int
    get() = this.a

class Holder {
    fun <T> List<T>.doubled()
        : List<T> {
        return this + this
    }
}

fun main() {
    println(Box(41).asIs().a)
    println(Box(1).plusOne().a)
    println(Box(7).intValue)
    println(Holder().run { listOf(1, 2).doubled() })
}
