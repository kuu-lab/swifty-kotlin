// Class-body stored property initializers (`var`/`val ... = expr` declared in
// the class body, not as a primary-constructor parameter) must actually run
// and land in the per-instance field. Covers: a class with no primary
// constructor, a class whose primary constructor also has parameters, a
// property with no explicit type annotation referenced from a same-class
// function, an `object` singleton, and multiple properties interleaved with
// `init` blocks so later initializers observe earlier ones' effects.
class Plain {
    var a: Int = 10
}

class WithCtorParam(val dummy: Int) {
    private var a: Int = 10
    fun get(): Int = a
}

class InferredType {
    var a = 10
    fun get(): Int = a
}

object Singleton {
    var count = 0
    fun bump(): Int {
        count += 7
        return count
    }
}

class Interleaved(val seed: Int) {
    val first: Int = seed + 1
    var second: Int = 2
    init { second += first }
    val third: Int = first + second
    var fourth: Int = 4
    init { fourth += third }
}

fun main() {
    println(Plain().a)
    println(WithCtorParam(0).get())
    println(InferredType().get())
    println(Singleton.bump())
    val m = Interleaved(100)
    println(m.first)
    println(m.second)
    println(m.third)
    println(m.fourth)
}
