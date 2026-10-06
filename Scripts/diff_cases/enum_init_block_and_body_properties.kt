// Enum `init {}` blocks and body property initializers run once per entry,
// in declaration order, on first access to the enum class.
enum class E { A, B; init { println("init " + name) } }

enum class Sq(val n: Int) {
    P(3), Q(4);
    val sq = n * n
    var hits = 0
    val described: String
    init { described = "$name:$sq" }
}

fun main() {
    println("start")
    println(E.A)
    println(E.B)
    Sq.P.hits++
    Sq.P.hits += 2
    Sq.Q.hits = 10
    println(Sq.P.sq)
    println(Sq.Q.sq)
    println(Sq.P.hits)
    println(Sq.Q.hits)
    println(Sq.Q.described)
}
