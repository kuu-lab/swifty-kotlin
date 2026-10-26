// KUU-3519: synthesized data-class toString must render Unit fields as kotlin.Unit.
data class A(val x: Unit)
data class NullableA(val x: Unit?)

fun main() {
    val a = A(Unit)
    println(a.toString())
    println(a)
    println(a.component1())

    println(NullableA(Unit))
    println(NullableA(null))
}
