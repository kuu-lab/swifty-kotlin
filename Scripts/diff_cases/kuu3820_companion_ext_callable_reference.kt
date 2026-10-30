// DIFF_CANDIDATE_ONLY: companion blocks/extensions need kotlinc's -Xcompanion-blocks-and-extensions, which the diff harness does not pass.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu3820_companion_ext_callable_reference.expected
// KUU-3820: `Type::member` callable references must pick the bound companion
// interpretation under each overload's parameter type — including companion
// extension functions shadowed by instance members — and keep the captured
// receiver after per-candidate re-inference.
class C {
    fun baz(x: Int) {}
    fun fooExt(x: Int) {}

    companion {
        fun foo(): String = "OK"
        fun bar(s: String) = s
        fun baz(s: String) = s

        val readonly = "OK"
        var mutable = "FAIL"
    }
}

companion fun C.fooExt(): String = "OK"
companion fun C.barExt(s: String) = s

inline fun inline(s: () -> String): String = s()
inline fun inline(s: (String) -> String): String = s("OK")

fun main() {
    println((C::foo)())
    println(inline(C::foo))
    println((C::bar)("OK"))
    println(inline(C::bar))
    println(inline(C::baz))

    println((C::readonly)())
    println(inline(C::readonly))

    C::mutable.set("OK")
    println((C::mutable)())
    println(inline(C::mutable))

    println((C::fooExt)())
    println(inline(C::fooExt))
    println((C::barExt)("OK"))
    println(inline(C::barExt))
}
