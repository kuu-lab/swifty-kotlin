// Primary constructor parameters declared without `val`/`var` (e.g. `class Foo(seed: Int)`)
// don't become members, so unlike val/var-backed parameters they aren't reachable through
// classScope. Kotlin still scopes them to property initializers and `init {}` blocks in the
// same class body (just not to regular member functions declared later), which requires
// resolving them through locals instead. Covers a property initializer referencing the
// parameter, an init block reading and mutating a property with it, and multiple
// init blocks/property initializers interleaved in declaration order.
class Accumulator(seed: Int) {
    var total: Int = seed
    init {
        total += seed
    }
}

class Doubler(input: Int) {
    val doubled: Int = input * 2
    val tripled: Int
    init {
        tripled = input * 3
    }
    val quadrupled: Int = doubled * 2
}

fun main() {
    val a = Accumulator(5)
    println(a.total)
    val d = Doubler(7)
    println(d.doubled)
    println(d.tripled)
    println(d.quadrupled)
}
