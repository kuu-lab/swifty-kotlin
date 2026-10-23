class SubEx(message: String?, cause: Throwable?) : Throwable(message, cause)

fun main() {
    val s: String? = "OK"
    val t: Throwable? = Throwable("test", null)

    val z = Throwable(s, t)
    println(z.message === s)
    println(z.cause === t)
    println(z.message === z.message)

    val z2 = Throwable(s)
    println(z2.message === s)
    println(z2.cause === null)

    val z3 = Throwable(t)
    println(z3.message)
    println(z3.cause === t)
    println(z3.message === z3.message)

    val z4 = Throwable()
    println(z4.message === null)
    println(z4.cause === null)

    // Typed exception ctors keep the argument String's identity too.
    println(IllegalStateException(s).message === s)
    println(IllegalStateException(s, t).cause === t)
    println(RuntimeException(s).message === s)

    // Kotlin-defined subclass through the 4-arg protected ctor path.
    println(SubEx(s, t).message === s)
    println(SubEx(s, t).cause === t)

    // AssertionError(Any?) keeps identity only for actual String args.
    println(AssertionError(s).message === s)
    println(AssertionError(42).message === "42")

    // initCause stores the raw handle.
    val e = Throwable()
    e.initCause(t)
    println(e.cause === t)
}
