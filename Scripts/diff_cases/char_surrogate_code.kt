// SKIP-DIFF (DEBT-DIFF-001): Char.Companion code-point helpers are Kotlin/Native-only APIs not available in kotlinc.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

fun main() {
    // Char surrogate predicates (KSP-663)
    println('\uD800'.isSurrogate())
    println('A'.isSurrogate())
    println('\uD800'.isHighSurrogate())
    println('\uDC00'.isHighSurrogate())
    println('\uDC00'.isLowSurrogate())
    println('\uD800'.isLowSurrogate())

    // Char.Companion code-point helpers
    println(Char.isSupplementaryCodePoint(0x10000))
    println(Char.isSupplementaryCodePoint(0xFFFF))
    println(Char.isSurrogatePair('\uD800', '\uDC00'))
    println(Char.isSurrogatePair('\uDC00', '\uD800'))
    println(Char.toCodePoint('\uD800', '\uDC00'))
    println(Char.toCodePoint('\uDBFF', '\uDFFF'))

    val bmp = Char.toChars(0x0041)
    println(bmp.size)
    println(bmp[0].code)

    val supp = Char.toChars(0x10000)
    println(supp.size)
    println(supp[0].code)
    println(supp[1].code)

    val max = Char.toChars(0x10FFFF)
    println(max.size)
    println(max[0].code)
    println(max[1].code)
}
