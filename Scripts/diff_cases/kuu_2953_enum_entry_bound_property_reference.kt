// KUU-2953: a bound property reference formed inside an enum entry must read
// the entry's ordinal-backed storage, not a never-written field/global slot.
enum class X {
    B {
        override val value = "OK"
        val bmr = this::value.get()
        override fun foo() = bmr
    };
    abstract val value: String
    abstract fun foo(): String
}

// A mutable constructor property still needs real per-entry storage even when
// every constructor argument is a literal.
enum class M(var v: Int) {
    P(1), Q(2)
}

fun main() {
    println(X.B.foo())
    M.P.v = 99
    println(M.P.v)
    val ref = M.Q::v
    ref.set(7)
    println(ref.get())
    println(M.Q.v)
    println(M.P.v)
}
