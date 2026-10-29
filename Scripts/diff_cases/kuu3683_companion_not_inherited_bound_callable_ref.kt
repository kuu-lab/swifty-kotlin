// KUU-3683 negative companion: when the companion does NOT inherit `B`,
// extensions declared on `B.Companion` still bind the singleton through
// the class-name form (`B::companionExt`), matching kotlinc. Members of
// `B` itself stay rejected (covered by Sema tests since diff cases need
// both compilers to succeed).
open class B {
    companion object {
        fun companion() = true
        val companionProp = true
    }
}
fun B.Companion.companionExt() = true
val B.Companion.companionExtProp get() = true

inline fun call(f: () -> Boolean) = f()

fun main() {
    println(call(B::companionExt))
    println(call(B::companionExtProp))
    println(call(B::companion))
    println(call(B::companionProp))
}
