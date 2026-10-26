// KUU-3282: context member extensions retain dispatch, extension, and context receivers through interface dispatch.
class A(val a: String)
interface I<T> { context(a: A) fun T.foo(): String }
object O : I<A> { context(a: A) override fun A.foo() = a.a }

fun throughInterface(i: I<A>): String = with(A("OK")) {
    with(i) { A("x").foo() }
}

fun main() {
    with(A("OK")) {
        with(O as I<A>) {
            println(A("x").foo())
        }
    }
    println(throughInterface(O))
}
