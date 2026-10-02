// BUG: a bare mutable-local operand in an ordinary binary expression or a
// function/method call's argument list returned that local's persistent
// storage register by identity. Since KIR instructions execute in append
// order, a later-evaluated sibling operand that mutated the same register
// (e.g. `x++` as a later operand/argument) was observed by an
// earlier-evaluated sibling that read the same variable, instead of the
// value at the point that earlier sibling was evaluated.
fun combine(a: Int, b: Int): String = "$a,$b"

class Combiner {
    fun combine(a: Int, b: Int): String = "$a,$b"
}

fun main() {
    var x = 5
    x = x + x++
    println(x)

    var y = 5
    y = y++ + y
    println(y)

    var p = 5
    val callResult = combine(p, p++)
    println(callResult)
    println(p)

    var q = 5
    val combiner = Combiner()
    val memberCallResult = combiner.combine(q, q++)
    println(memberCallResult)
    println(q)
}
