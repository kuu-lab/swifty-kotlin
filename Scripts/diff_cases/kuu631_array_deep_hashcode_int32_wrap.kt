// KUU-631: Array.contentDeepHashCode() is java.util.Arrays.deepHashCode —
// result = 31 * result + elementHashCode(element) folded in 32-bit wrapping
// Int at every step (recursing into nested arrays). KSwiftK's runtime bridge
// accumulated in 64-bit Int, so any fold whose running total leaves Int32
// range — deep nesting, long arrays, or large-hashCode elements — diverged
// from kotlinc.

fun main() {
    // The Linear repro: a 3-deep tree whose combines overflow Int32.
    val deep8 = arrayOf(
        arrayOf(arrayOf(1, 2), arrayOf(3, 4)),
        arrayOf(arrayOf(5, 6), arrayOf(7, 8)),
        arrayOf(arrayOf(9, 10), arrayOf(11, 12))
    )
    println(deep8.contentDeepHashCode())

    // A shallow array still overflows once element hashCodes are large:
    // string elements push 31*acc + h past Int32 within 2-3 combines.
    val strings = arrayOf(
        "averylongstringvaluethathashesbig",
        "anotherlongstringvalueforthepair",
        "yetanotherstringtooverflow"
    )
    println(strings.contentDeepHashCode())

    // Long flat arrays wrap mid-fold even with small Int elements.
    val longFlat = Array(40) { it * 31 + 7 }
    println(longFlat.contentDeepHashCode())

    // Nested arrays recurse: IntArray elements hash as their Int values and
    // a nested object array folds supplementary-plane string hashCodes.
    val intNested: Array<Any?> = arrayOf(
        intArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10),
        arrayOf("𐀀", "😀")
    )
    println(intNested.contentDeepHashCode())

    // Consistency: equal deep content must hash equally, and differ for
    // different content.
    val left = arrayOf(arrayOf(1, 2), arrayOf(3, 4))
    val same = arrayOf(arrayOf(1, 2), arrayOf(3, 4))
    val different = arrayOf(arrayOf(1, 2), arrayOf(4, 3))
    println(left.contentDeepHashCode() == same.contentDeepHashCode())
    println(left.contentDeepHashCode() == different.contentDeepHashCode())
    println(left.contentDeepHashCode())
    println(different.contentDeepHashCode())
}
