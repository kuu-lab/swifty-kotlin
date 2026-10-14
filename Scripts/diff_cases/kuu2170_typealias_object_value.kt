object Obj { val x = 42; operator fun invoke(n: Int) = n + 1; fun f() = "f" }
typealias A = Obj
class C { companion object { val y = 7; fun g() = "g" } }
typealias CA = C
fun main() {
    println(A.x)
    println(A.f())
    println(A(1))
    println(CA.y)
    println(CA.g())
    val o = A
    println(o.x)
}
