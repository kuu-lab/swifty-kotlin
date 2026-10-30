// KUU-3683: `A::member` where `companion object : A()` also carries a
// bound interpretation on the `A.Companion` singleton, so an expected
// `() -> Boolean` selects the bound form (JetBrains
// callableReference/bound/companionObjectReceiverInheritsFromOuter.kt).
// Companion-declared members/extensions bind the singleton
// unconditionally; members/extensions of `A` require the inheritance.
// `callContext`-style expected types are a separate unsupported gap.
open class A {
    fun instance() = true
    val instanceProp = true
    companion object : A() {
        fun companion() = true
        val companionProp = true
    }
}
fun A.ext() = true
val A.extProp get() = true
fun A.Companion.companionExt() = true
val A.Companion.companionExtProp get() = true

inline fun call(f: () -> Boolean) = f()

fun main() {
    // Bound interpretation on the companion singleton.
    println(call(A::instance))
    println(call(A::ext))
    println(call(A::companionExt))
    println(call(A::companion))
    println(call(A::instanceProp))
    println(call(A::extProp))
    println(call(A::companionExtProp))
    println(call(A::companionProp))
    // Unbound interpretation still wins for (A) -> Boolean.
    val unboundMember: (A) -> Boolean = A::instance
    println(unboundMember(A.Companion))
    val unboundExt: (A) -> Boolean = A::ext
    println(unboundExt(A.Companion))
}
