// KUU-3206: extension getValue/setValue declared after the delegated property
// must still resolve. kotlinc accepts these; kswiftc reported SEMA-0103.
class C {
    val impl = 123
    val s: String by impl
    var t: String by impl
}
operator fun Any?.getValue(thisRef: Any?, property: Any?) =
    if (this == 123) "OK" else "Failed"
operator fun Any?.setValue(thisRef: Any?, property: Any?, value: String) {}

fun local(): String {
    val impl = 7
    val s: String by impl
    return s
}
operator fun Int.getValue(thisRef: Any?, property: Any?) = "LOCAL"

fun main() {
    val c = C()
    println(c.s)
    c.t = "x"
    println(c.t)
    println(local())
}
