// Regression for KUU-4006: an expression-bodied anonymous function inside a
// lambda body was rejected with KSWIFTK-SEMA-0426 "function 'anonymous' must
// have a body." The lambda statement probe tried the assignment parse first,
// which split `fun(): Int = it * it` at `=` and parsed the LHS as a bodiless
// anonymous function — leaking the diagnostic because lambda-body probes did
// not roll back failed speculations the way block/statement probes do.
fun main() {
    val funcs = Array(3) { fun(): Int = it * it }
    println(funcs[0]())
    println(funcs[2]())

    // Multi-statement lambda bodies keep the anonymous function as the
    // trailing expression value.
    val offset = 10
    val shifted = Array(2) {
        val base = it + offset
        fun(): Int = base * 2
    }
    println(shifted[1]())

    // Assignments in lambda bodies still parse as assignment statements.
    var acc = 0
    listOf(1, 2, 3).forEach { acc = acc + it }
    println(acc)

    val runResult = run { fun(): Int = 7 }
    println(runResult())

    val labeled = label@ fun(x: Int): Int = x + 1
    println(labeled(4))

    // Anonymous extension functions in statement position are not named
    // local functions either: `this` binds to the declared receiver.
    val ext = fun Int.(): Int = this + 1
    println(5.ext())
    val scaled = Array(3) { fun Int.(): Int = this * it }
    println(scaled[2].let { f -> 10.f() })

    listOf(1).forEach {
        fun Int.named(): Int = this + it
        println(1.named())
    }
}
