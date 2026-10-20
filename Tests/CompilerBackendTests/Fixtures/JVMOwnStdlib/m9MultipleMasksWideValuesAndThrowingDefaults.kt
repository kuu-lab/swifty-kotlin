fun many(p0: Int = 1, p1: Int = 2, p2: Int = 3, p3: Int = 4, p4: Int = 5, p5: Int = 6, p6: Int = 7, p7: Int = 8, p8: Int = 9, p9: Int = 10, p10: Int = 11, p11: Int = 12, p12: Int = 13, p13: Int = 14, p14: Int = 15, p15: Int = 16, p16: Int = 17, p17: Int = 18, p18: Int = 19, p19: Int = 20, p20: Int = 21, p21: Int = 22, p22: Int = 23, p23: Int = 24, p24: Int = 25, p25: Int = 26, p26: Int = 27, p27: Int = 28, p28: Int = 29, p29: Int = 30, p30: Int = 31, p31: Int = 32, p32: Int = 33, p33: Int = 34): Int = p0 + p31 + p32 + p33
class Wide(val first: Long = 40L, val second: Double = 2.0, val text: String = "wide")
fun fail(): Int { throw IllegalStateException("default") }
fun optional(n: Int = fail()): Int = n
fun nullable(text: String? = null): String? = text
fun direct(n: Int = throw IllegalStateException("direct")): Int = n
inline fun stop(n: Int = throw IllegalStateException("stop")): Int = n
fun main() {
    println(many()); println(many(p33 = 1, p0 = 2)); println(many(p31 = 3, p32 = 4))
    val wide = Wide(second = 3.5)
    println(wide.first); println(wide.second); println(wide.text)
    println(optional(n = 42))
    try { println(optional()) } catch (error: IllegalStateException) { println("caught") }
    println(nullable()); println(nullable(text = "provided"))
    try { direct() } catch (error: IllegalStateException) { println("direct") }
    try { stop() } catch (error: IllegalStateException) { println("stop") }
    println(direct(n = 42))
}
