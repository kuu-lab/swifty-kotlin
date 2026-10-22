// KUU-3017: a top-level factory function sharing the class name (different
// signature) must coexist with the constructor and link.
class Y(val a: Int)

fun Y(s: String) = Y(s.length)

fun Z() = 1

class Z(val a: Int)

fun main() {
    println(Y(3).a)
    println(Y("ab").a)
    println(Z())
    println(Z(2).a)
}
