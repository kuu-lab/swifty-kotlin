// KUU-3529: an early `return` inside a secondary constructor must leave the
// constructed instance, not Unit — a bare `return` used to produce a Unit
// result, so the caller saw a garbage receiver and reading `prop` trapped.
//
// Oracle: JetBrains/Kotlin compiler/testData/codegen/box/secondaryConstructors/withReturn.kt
class A {
    val prop: Int
    constructor(arg: Boolean) {
        if (arg) {
            prop = 1
            return
        }
        prop = 2
    }
}

fun box(): String {
    val a1 = A(true)
    if (a1.prop != 1) return "fail1: ${a1.prop}"
    val a2 = A(false)
    if (a2.prop != 2) return "fail2: ${a2.prop}"
    return "OK"
}

fun main() {
    println(A(true).prop)
    println(A(false).prop)
    println(box())
}
