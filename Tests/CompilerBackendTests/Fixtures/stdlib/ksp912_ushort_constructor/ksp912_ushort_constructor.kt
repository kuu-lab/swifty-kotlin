@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

private fun show(label: String, value: UShort) {
    println("$label=$value")
    val boxed: Any = value
    println("$label-is=${boxed is UShort}")
    println("$label-boxed=${(boxed as UShort).toInt()}")
}

fun main() {
    show("zero", UShort(0.toShort()))
    show("max", UShort(Short.MAX_VALUE.toShort()))
    show("minusOne", UShort((-1).toShort()))
    show("min", UShort(Short.MIN_VALUE.toShort()))

    val inferred = UShort(0.toShort())
    val typed: UShort = UShort((-1).toShort())
    println("inferred=$inferred typed=$typed")
}
