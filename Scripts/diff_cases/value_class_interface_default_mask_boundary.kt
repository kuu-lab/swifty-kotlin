// KUU-3231: the default-argument mask's in-band super-call marker sits at bit
// 30, so a member stub for 31+ defaulted parameters must carry the marker in a
// separate trailing word. Otherwise an omitted parameter at index 30 is
// misread as a super call and virtual dispatch is skipped (JetBrains
// inlineClasses/kt57973.kt).
interface IIC33 {
    fun f(
        i1: Long = 1, i2: Long = 2, i3: Long = 3, i4: Long = 4, i5: Long = 5,
        i6: Long = 6, i7: Long = 7, i8: Long = 8, i9: Long = 9, i10: Long = 10,
        i11: Long = 11, i12: Long = 12, i13: Long = 13, i14: Long = 14, i15: Long = 15,
        i16: Long = 16, i17: Long = 17, i18: Long = 18, i19: Long = 19, i20: Long = 20,
        i21: Long = 21, i22: Long = 22, i23: Long = 23, i24: Long = 24, i25: Long = 25,
        i26: Long = 26, i27: Long = 27, i28: Long = 28, i29: Long = 29, i30: Long = 30,
        i31: Long = 31, i32: Long = 32, i33: Long = 33,
    ): Long

    fun g(
        i1: Long = 1, i2: Long = 2, i3: Long = 3, i4: Long = 4, i5: Long = 5,
        i6: Long = 6, i7: Long = 7, i8: Long = 8, i9: Long = 9, i10: Long = 10,
        i11: Long = 11, i12: Long = 12, i13: Long = 13, i14: Long = 14, i15: Long = 15,
        i16: Long = 16, i17: Long = 17, i18: Long = 18, i19: Long = 19, i20: Long = 20,
        i21: Long = 21, i22: Long = 22, i23: Long = 23, i24: Long = 24, i25: Long = 25,
        i26: Long = 26, i27: Long = 27, i28: Long = 28, i29: Long = 29, i30: Long = 30,
        i31: Long = 31, i32: Long = 32,
    ): Long
}

@JvmInline
value class IC(val x: Long) : IIC33 {
    override fun f(
        i1: Long, i2: Long, i3: Long, i4: Long, i5: Long,
        i6: Long, i7: Long, i8: Long, i9: Long, i10: Long,
        i11: Long, i12: Long, i13: Long, i14: Long, i15: Long,
        i16: Long, i17: Long, i18: Long, i19: Long, i20: Long,
        i21: Long, i22: Long, i23: Long, i24: Long, i25: Long,
        i26: Long, i27: Long, i28: Long, i29: Long, i30: Long,
        i31: Long, i32: Long, i33: Long,
    ) = i1 + i2 + i3 + i4 + i5 + i6 + i7 + i8 + i9 + i10 +
        i11 + i12 + i13 + i14 + i15 + i16 + i17 + i18 + i19 + i20 +
        i21 + i22 + i23 + i24 + i25 + i26 + i27 + i28 + i29 + i30 +
        i31 + i32 + i33

    override fun g(
        i1: Long, i2: Long, i3: Long, i4: Long, i5: Long,
        i6: Long, i7: Long, i8: Long, i9: Long, i10: Long,
        i11: Long, i12: Long, i13: Long, i14: Long, i15: Long,
        i16: Long, i17: Long, i18: Long, i19: Long, i20: Long,
        i21: Long, i22: Long, i23: Long, i24: Long, i25: Long,
        i26: Long, i27: Long, i28: Long, i29: Long, i30: Long,
        i31: Long, i32: Long,
    ) = i1 + i2 + i3 + i4 + i5 + i6 + i7 + i8 + i9 + i10 +
        i11 + i12 + i13 + i14 + i15 + i16 + i17 + i18 + i19 + i20 +
        i21 + i22 + i23 + i24 + i25 + i26 + i27 + i28 + i29 + i30 +
        i31 + i32
}

fun main() {
    println(IC(2).f())
    println(IC(2).g())
    println(IC(2).f(i33 = 1000))
}
