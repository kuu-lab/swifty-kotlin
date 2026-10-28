// KUU-3674: `B::foo` must prefer the package-level extension over the
// companion member (Kotlin 1.4 rule; JetBrains
// callableReference/function/referenceToCompanionMember.kt).
class A {
    companion object {
        fun foo(): String = "A"
    }
}

class B {
    companion object {
        fun foo(): String = "B-companion"
    }
}

fun B.foo(): String = "B-extension"

fun box(): String {
    val call1 = A::foo
    if (call1 is Function1<*, *> || call1() != "A") return "fail 1"

    // Checking compatibility mode: resolved to extensions since Kotlin 1.4.
    val call2 = B::foo
    if (call2 !is Function1<*, *>) return "fail 2 arity"
    val invoked = call2.invoke(B())
    if (invoked != "B-extension") return "fail 2: $invoked"
    return "OK"
}

fun main() {
    println(box())

    // An expected function type still selects between the two shapes:
    // `() -> String` fits only the bound companion member, while
    // `(B) -> String` fits only the unbound extension.
    val bound: () -> String = B::foo
    println(bound())
    val unbound: (B) -> String = B::foo
    println(unbound(B()))
}
