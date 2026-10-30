// KUU-3141: Adapted from Kotlin 2.3.10's pinned
// compiler/testData/codegen/box/objects/nestedDerivedClassCallsProtectedFromCompanion.kt.
// Upstream commit: 679366a83f99851b42f64795f10ed803ff011c73
// Upstream source SHA-256: ecc3586b75e48e8f09cb432185eb00811d127cf1efcca8ade34022a4faaf1d2b
// Kotlin/JVM also accepts calls to a companion's protected member from the
// containing class's own members; subclasses that are not lexically nested
// inside the containing class remain rejected — see
// Scripts/diagnostic_cases/reject_protected_companion_from_superclass.kt.
open class A {
    companion object {
        protected fun foo() = "OK"
    }
    class B : A() {
        fun bar() = foo()
    }
    fun outer() = foo()
}

fun box() = A.B().bar()

fun main() {
    println(box())
    println(A().outer())
}
