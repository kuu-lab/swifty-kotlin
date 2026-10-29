// Regression: a SAM conversion built from a callable reference whose context
// receiver sits in the receiver position (`C::prop`, `C::describe` adapt
// `(C) -> R`/`C.() -> R` to `context(C) () -> R`) produced a bare
// KProperty/function value instead of a SAM wrapper, so interface dispatch
// crashed at the call site (KUU-3170).
class C(val value: String) {
    val prop: String get() = value
    fun describe(): String = value + "d"
}

fun interface Sam {
    context(c: C)
    fun accept(): String
}

fun main() {
    val sam = Sam(C::prop)
    val sam2 = Sam(C::describe)
    with(C("OK")) {
        println(sam.accept())
        println(sam2.accept())
    }
}
