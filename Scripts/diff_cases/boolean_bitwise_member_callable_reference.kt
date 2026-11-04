// KUU-4092: unbound `Boolean::and` / `::or` / `::xor` are intrinsic members
// (upstream: `infix fun` members of kotlin.Boolean) with no backing decl, so
// they resolve through the primitive-operator reference path like
// `Boolean::not`. The unique `(Boolean, Boolean) -> Boolean` signature
// resolves without an expected type and KCallable.name reflects the member.
val andRef: (Boolean, Boolean) -> Boolean = Boolean::and
val orRef = Boolean::or
val xorRef = Boolean::xor

fun box(): String {
    if (!andRef(true, true)) return "Fail andRef"
    if (andRef(true, false)) return "Fail andRef false"
    if (!orRef(false, true)) return "Fail orRef"
    if (xorRef(true, true)) return "Fail xorRef"
    if (!xorRef(true, false)) return "Fail xorRef true"
    if (Boolean::and.name != "and") return "Fail and.name"
    if (Boolean::or.name != "or") return "Fail or.name"
    if (Boolean::xor.name != "xor") return "Fail xor.name"
    if ((Boolean::and).let { it(true, false) }) return "Fail let and"
    if (!(Boolean::or).let { it(false, true) }) return "Fail let or"
    if ((Boolean::xor).let { it(true, true) }) return "Fail let xor"
    return "OK"
}

fun main() {
    println(box())
    println(Boolean::and.name)
    println(Boolean::or.name)
    println(Boolean::xor.name)
    println(andRef(true, false))
    println(orRef(false, true))
    println(xorRef(true, true))
    println(listOf(true, false).fold(true, Boolean::and))
    println(listOf(false, true).fold(false, Boolean::or))
    println(listOf(true, true).fold(false, Boolean::xor))
}
