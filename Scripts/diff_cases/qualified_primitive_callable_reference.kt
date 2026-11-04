// KUU-4137: package-qualified `kotlin.X::member` receivers hit the same
// intrinsic/member paths as the bare `X::member` forms -- `kotlin.Int::plus`
// parses as a memberCall qualifier chain, not a nameRef, so the primitive
// operator reference path must accept the qualified shape too.
val plusRef: (Int, Int) -> Int = kotlin.Int::plus
val timesRef: (Int, Int) -> Int = kotlin.Int::times
val andRef: (Boolean, Boolean) -> Boolean = kotlin.Boolean::and
val orRef = kotlin.Boolean::or
val xorRef = kotlin.Boolean::xor
val notRef: (Boolean) -> Boolean = kotlin.Boolean::not

fun box(): String {
    if (plusRef(2, 3) != 5) return "Fail plus"
    if (timesRef(2, 3) != 6) return "Fail times"
    if (!andRef(true, true)) return "Fail and"
    if (andRef(true, false)) return "Fail and false"
    if (!orRef(false, true)) return "Fail or"
    if (xorRef(true, true)) return "Fail xor"
    if (!xorRef(true, false)) return "Fail xor true"
    if (!notRef(false)) return "Fail not"
    if (kotlin.Boolean::and.name != "and") return "Fail and.name"
    return "OK"
}

fun main() {
    println(box())
    println(kotlin.Boolean::or.name)
    println(listOf(1, 2, 3).fold(0, kotlin.Int::plus))
    println(listOf(true, false).fold(true, kotlin.Boolean::and))
    println(listOf(2L, 3L).fold(1L, kotlin.Long::times))
}
