// A generic class whose property getter (or member function) returns the
// class type parameter `T` must type-check: the implicit receiver of the
// class body is `Box<T>`, so `val alias: T get() = value` and
// `fun idFun(): T = value` resolve `T` as the member's own type parameter
// rather than leaving it unsubstituted. Regression for KSP-608, where
// source-backed `Pair`/`Triple` getters returning `A`/`B`/`C` first exposed
// the receiver-substitution gap.
class Box<T>(val value: T) {
    fun idFun(): T = value
    fun aliasViaFun(): T = idFun()

    val alias: T
        get() = value

    val aliasViaCall: T
        get() = idFun()
}

fun main() {
    val b = Box(42)
    println(b.value)
    println(b.idFun())
    println(b.aliasViaFun())
    println(b.alias)
    println(b.aliasViaCall)

    val s = Box("hi")
    println(s.alias)
    println(s.aliasViaCall)

    val nested = Box(Box(7))
    println(nested.value.alias)
}
