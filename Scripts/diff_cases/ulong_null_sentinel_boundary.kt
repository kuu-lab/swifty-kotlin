fun show(x: Any?) {
    println(x)
}

@OptIn(ExperimentalStdlibApi::class)
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

    val hexULong = "8000000000000000".hexToULong()
    show(hexULong)

    val hexLong = "8000000000000000".hexToLong()
    show(hexLong)

    // A nullable ULong away from the sentinel boundary must render correctly
    // through string-template interpolation, which dispatches via a compiler-
    // emitted kk_any_to_string(_nullable) call carrying an explicit tag rather
    // than going through generic Any-boxing dispatch.
    val taggedU: ULong? = 17663719463477156090uL
    println("taggedU=$taggedU")
}
