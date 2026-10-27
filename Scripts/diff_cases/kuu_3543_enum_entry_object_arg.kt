// KUU-3543: an anonymous `object : T {}` expression must be accepted as an
// enum-entry constructor argument, and the entry must resolve inside it.
// KUU-3542: the enum entry itself must resolve inside its own anonymous-class
// body (inner-class supertype args, `by` delegates, member bodies).
interface Callback { fun invoke(): String }
abstract class Base(val cb: Callback)
interface Greeter { fun greet(): String }

enum class WithObjectArg(val x: String, val callback: Callback) {
    FOO(
        "OK",
        object : Callback {
            override fun invoke() = FOO.x
        }
    )
}

enum class SelfRef(val x: String) : Greeter {
    ENTRY("E") {
        inner class Inner : Base(object : Callback {
            override fun invoke() = ENTRY.x
        })
        val z = Inner()
        override fun greet() = z.cb.invoke()
    }
}

fun main() {
    println(WithObjectArg.FOO.callback.invoke())
    println(SelfRef.ENTRY.greet())
}
