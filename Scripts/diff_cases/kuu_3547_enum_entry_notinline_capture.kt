// KUU-3547 (JetBrains codegen/box/enum/kt7257_notInline): a lambda passed
// to a non-inline helper inside an enum entry body captures the entry's own
// member through the implicit `this` receiver. The captured entry reference
// must stay valid through every lambda ABI shape: the auto-inlined helper
// (flat String arguments bound to erased parameters are boxed first), an
// explicit `noinline` parameter (a real closure object at the call site),
// and a stored function-typed property invoked through the closure ABI.
// Historically the flat String aggregate reached kk_string_to_flat unboxed
// and a field was dereferenced as an out-pointer (SIGSEGV).
fun <T, R> T.letNoInline(fn: (T) -> R) = fn(this)
inline fun <T, R> T.letInlineNoInline(noinline fn: (T) -> R) = fn(this)

enum class X {
    B {
        val value2 = "K"
        val stored: (String) -> String = { it + value2 }
        override val value = "O".letNoInline { it + value2 } +
            "|" + "O".letInlineNoInline { it + value2 } +
            "|" + "O".letNoInline(stored)
    };
    abstract val value: String
}

fun main() { println(X.B.value) }
