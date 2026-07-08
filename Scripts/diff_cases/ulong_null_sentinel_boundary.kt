fun show(x: Any?) {
    println(x)
}

fun main() {
    val big: ULong = 9223372036854775808uL
    val any: Any = big
    println(any)

    val nullU: ULong? = null
    val anyNull: Any? = nullU
    println(anyNull)
    show(nullU)

    val presentU: ULong? = 9223372036854775808uL
    val anyPresent: Any? = presentU
    println(anyPresent)
    show(presentU)

    val bigL: Long = Long.MIN_VALUE
    val anyL: Any = bigL
    println(anyL)

    val nullL: Long? = null
    show(nullL)

    val presentL: Long? = Long.MIN_VALUE
    show(presentL)
}
