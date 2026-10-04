// Regression: Throwable.message / cause were final, so `override val message`
// was rejected (KSWIFTK-SEMA-FINAL); toString() and string templates must also
// dispatch to the overridden message.
class Coded(val code: Int) : Exception() {
    override val message: String get() = "code=$code"
}

class NullMessage : Exception("stored") {
    override val message: String? get() = null
}

open class Base(msg: String) : Exception(msg)

class Derived : Base("base") {
    override val message: String get() = "derived:" + super.message
}

class WithCause : RuntimeException("wrapped") {
    override val cause: Throwable? = IllegalStateException("inner")
}

fun main() {
    println(Coded(4).message)
    println(Coded(4))
    println("${Coded(7)}")
    val t: Throwable = Coded(5)
    println(t.message)
    println(t.toString())
    println(NullMessage().message)
    println(NullMessage())
    println(Derived().message)
    println(Derived())
    println(WithCause().cause?.message)
    try {
        throw Coded(9)
    } catch (e: Exception) {
        println("caught " + e.message + " / " + e)
    }
    println(IllegalStateException("plain"))
    println(IllegalArgumentException())
    println(RuntimeException("r", IllegalStateException("c")).cause?.message)
}
