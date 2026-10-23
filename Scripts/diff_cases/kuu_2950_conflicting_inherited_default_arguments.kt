// DIFF_JVM
// KUU-2950 / KT-36188: when an override inherits the same member through
// several supertypes, the first declared supertype's chain supplies the
// default argument values — even when the matching declaration sits deeper
// than a later supertype's. Forward order resolves through A2 to A ("OK");
// reversed order takes B's own default ("Fail").
interface ConflictingA {
    fun foo(a: String = "OK"): String
}
interface ConflictingA2 : ConflictingA
interface ConflictingB {
    fun foo(a: String = "Fail"): String
}
class ForwardImpl : ConflictingA2, ConflictingB {
    override fun foo(a: String) = a
}
class ReversedImpl : ConflictingB, ConflictingA2 {
    override fun foo(a: String) = a
}

// A branch that declares no default anywhere falls through to the next
// supertype's default.
interface NoDefaultA {
    fun bar(a: String): String
}
interface NoDefaultA2 : NoDefaultA
interface HasDefaultB {
    fun bar(a: String = "Fail"): String
}
class MissingFirstImpl : NoDefaultA2, HasDefaultB {
    override fun bar(a: String) = a
}

fun main() {
    println(ForwardImpl().foo())
    println(ReversedImpl().foo())
    println(MissingFirstImpl().bar())
}
