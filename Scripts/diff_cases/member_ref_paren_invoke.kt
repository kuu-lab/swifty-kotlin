class D { fun f() = 3 }
class E { fun g(x: Int) = x + 3 }

fun main() {
    println((D::f)(D()))
    println((E::g)(E(), 1))
}
