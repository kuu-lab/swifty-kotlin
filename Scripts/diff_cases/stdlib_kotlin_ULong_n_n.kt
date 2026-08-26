@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

private fun show(label: String, value: ULong) {
    println("$label=$value")
    val boxed: Any = value
    println("$label-is=${boxed is ULong}")
}

fun main() {
    show("zero", ULong(0L))
    show("one", ULong(1L))
    show("minusOne", ULong(-1L))
    show("min", ULong(Long.MIN_VALUE))
    show("max", ULong(Long.MAX_VALUE))

    val inferred = ULong(1L)
    val typed: ULong = ULong(-1L)
    println("inferred=$inferred typed=$typed")
}
