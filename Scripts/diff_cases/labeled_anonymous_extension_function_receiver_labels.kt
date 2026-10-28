// KUU-3527: both the anonymous function label and extension property name label its receiver.
class A(val x: String)

val <T> T.a: T.() -> String
    get() = fun1@ fun T.(): String { return (this@fun1 as A).x + (this@a as A).x }

fun main() {
    println(A("K").a(A("O")))
}
