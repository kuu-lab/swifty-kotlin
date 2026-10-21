package kliblatest

open class ManyBase {
    open fun many(
        p0: Int = 0, p1: Int = 1, p2: Int = 2, p3: Int = 3,
        p4: Int = 4, p5: Int = 5, p6: Int = 6, p7: Int = 7,
        p8: Int = 8, p9: Int = 9, p10: Int = 10, p11: Int = 11,
        p12: Int = 12, p13: Int = 13, p14: Int = 14, p15: Int = 15,
        p16: Int = 16, p17: Int = 17, p18: Int = 18, p19: Int = 19,
        p20: Int = 20, p21: Int = 21, p22: Int = 22, p23: Int = 23,
        p24: Int = 24, p25: Int = 25, p26: Int = 26, p27: Int = 27,
        p28: Int = 28, p29: Int = 29, p30: Int = 30
    ): Int = p30
}

class ManyDerived : ManyBase() {
    override fun many(
        p0: Int, p1: Int, p2: Int, p3: Int,
        p4: Int, p5: Int, p6: Int, p7: Int,
        p8: Int, p9: Int, p10: Int, p11: Int,
        p12: Int, p13: Int, p14: Int, p15: Int,
        p16: Int, p17: Int, p18: Int, p19: Int,
        p20: Int, p21: Int, p22: Int, p23: Int,
        p24: Int, p25: Int, p26: Int, p27: Int,
        p28: Int, p29: Int, p30: Int
    ): Int = p30 + 100
}

fun callManyDefaults(): Int {
    val base: ManyBase = ManyDerived()
    return base.many()
}
