// KUU-3545: a bound callable reference `::member` inside an enum entry body
// resolves through the entry's implicit receiver. Members declared on the
// entry's own anonymous class (extra stored properties and non-override
// functions) are owned by the entry field symbol `X.B` rather than the enum
// class `X`, so they need the lexical entry scope — not just receiver-type
// member lookup — to become candidates. Override members dispatch through
// the enum's `$enumEntryDispatch$` helper so the entry body implementation
// runs instead of the abstract base stub.
enum class X {
    B {
        override val value = "OK"
        val extra = "EXTRA"
        override fun foo() = "FOO"
        fun bar() = "BAR"
        override val test =
            (::value.get()) + "|" +
            (this::value.get()) + "|" +
            (::extra.get()) + "|" +
            (this::extra.get()) + "|" +
            (::foo.invoke()) + "|" +
            (this::foo.invoke()) + "|" +
            (::bar.invoke()) + "|" +
            (this::bar.invoke())
    };
    abstract val value: String
    abstract fun foo(): String
    abstract val test: String
}

// The implicit `::member` receiver in an ordinary class body already binds
// `this`; keep it next to the enum-entry shapes to pin the receiver rule.
class Greeter(val greeting: String) {
    fun greet() = greeting
    val implicit = ::greet.invoke()
    val explicit = this::greet.invoke()
}

fun main() {
    println(X.B.test)
    val greeter = Greeter("HI")
    println(greeter.implicit + "|" + greeter.explicit)
}
