interface A<T> { var v: T }
class B : A<String> { override var v: String = "x" }

fun main() {
    val b = B()
    b.v = "direct"
    println(b.v)

    val a: A<String> = b
    a.v = "OK"
    println(b.v)
}
