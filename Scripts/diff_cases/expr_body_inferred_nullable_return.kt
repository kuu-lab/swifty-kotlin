// Expression-body functions whose inferred return type is nullable must not be
// checked against the non-null `Any` header placeholder.
fun anyOrNull(): Any? = null
fun viaAny() = anyOrNull()

fun intOrNull(flag: Boolean): Int? = if (flag) 42 else null
fun viaInt(flag: Boolean) = intOrNull(flag)

inline fun <T> passThrough(x: T): Any? = x
fun viaInline() = passThrough(1)

class Box(val value: String?) {
    fun read() = value
    fun readOrNull(other: Box?) = other?.value
}

fun main() {
    println(viaAny())
    println(viaInt(true))
    println(viaInt(false))
    println(viaInline())
    println(Box("x").read())
    println(Box(null).read())
    println(Box("a").readOrNull(null))
    println(Box("a").readOrNull(Box("b")))
}
