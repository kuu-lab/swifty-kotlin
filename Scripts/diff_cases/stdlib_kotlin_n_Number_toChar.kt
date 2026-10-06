// KUU-1372: Number.toChar() on an erased Number receiver must dispatch like
// the other Number.to*() conversions. DEPRECATION_ERROR suppression keeps the
// case compiling under reference kotlinc whose default api-version is >= 2.3
// (toChar became a deprecation error in 2.3); older compilers that only warn
// are unaffected by the suppression.
@Suppress("DEPRECATION", "DEPRECATION_ERROR")
class Money(val cents: Int) : Number() {
    override fun toDouble() = cents / 100.0
    override fun toFloat() = (cents / 100.0).toFloat()
    override fun toLong() = (cents / 100).toLong()
    override fun toInt() = cents / 100
    override fun toShort() = (cents / 100).toShort()
    override fun toByte() = (cents / 100).toByte()
}

@Suppress("DEPRECATION", "DEPRECATION_ERROR")
fun <T : Number> viaGeneric(x: T): Char = x.toChar()

@Suppress("DEPRECATION", "DEPRECATION_ERROR")
fun main() {
    val n: Number = 65
    println(n.toChar())
    val d: Number = 65.9
    println(d.toChar())
    val l: Number = 66L
    println(l.toChar())
    val f: Number = 67.5f
    println(f.toChar())
    val b: Number = (-1).toByte()
    println(b.toChar().code)
    val s: Number = (-1).toShort()
    println(s.toChar().code)
    // A user-defined subclass that does not override toChar inherits the open
    // default implementation, which composes through the subclass's toInt().
    val m: Number = Money(6700)
    println(m.toChar())
    println(viaGeneric(70))
}
