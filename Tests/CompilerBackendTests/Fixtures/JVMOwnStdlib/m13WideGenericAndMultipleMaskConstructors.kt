@JvmInline value class Many(val value: Int) {
    constructor(tag: Long, p0: Int = 0, p1: Int = 1, p2: Int = 2, p3: Int = 3, p4: Int = 4, p5: Int = 5, p6: Int = 6, p7: Int = 7, p8: Int = 8, p9: Int = 9, p10: Int = 10, p11: Int = 11, p12: Int = 12, p13: Int = 13, p14: Int = 14, p15: Int = 15, p16: Int = 16, p17: Int = 17, p18: Int = 18, p19: Int = 19, p20: Int = 20, p21: Int = 21, p22: Int = 22, p23: Int = 23, p24: Int = 24, p25: Int = 25, p26: Int = 26, p27: Int = 27, p28: Int = 28, p29: Int = 29, p30: Int = 30, p31: Int = 31, p32: Int = 32): this(p0 + p31 + p32)
}
@JvmInline value class Wide(val value: Long = 9L) {
    constructor(a: Int, b: Long = a.toLong(), c: Long = b + 2L): this(c)
}
@JvmInline value class Generic<T>(val value: T) {
    constructor(values: List<T>, pick: Boolean = true): this(values[0])
}
class Holder {
    @JvmInline value class Nested(val value: Int) {
        constructor(b: Boolean): this(if (b) 9 else 8)
    }
}
var count = 0
fun fail(): Int { throw IllegalStateException("default") }
@JvmInline value class Checked(val value: Int = fail()) { init { count++ } }
fun main() {
    println(Many(1L, p31 = 100)); println(Wide()); println(Wide(4)); println(Wide(4, c = 20L))
    println(Generic<String>(listOf("hi")).value); println(Holder.Nested(true))
    try { Checked() } catch (e: IllegalStateException) { println(e.message) }
    println(count); val checked: Any = Checked(7); println(checked); println(count)
}
