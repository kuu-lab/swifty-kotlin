// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
package golden.sema

interface WithConcreteProperties {
    val concreteVal: String
        get() = "default"
    var concreteVar: Int
        get() = 42
        set(value) {}

    val computedVal: String
        get() = "computed"

    var computedVar: String
        get() = "get"
        set(value) { }
}

class InheritConcreteOnly : WithConcreteProperties

fun main() {
    val concrete = InheritConcreteOnly()
    println(concrete.concreteVal)
    println(concrete.concreteVar)
    println(concrete.computedVal)
}
