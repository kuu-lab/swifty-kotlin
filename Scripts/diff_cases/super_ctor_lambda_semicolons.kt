// KUU-1171: semicolons inside superclass arguments must not end the declaration.
abstract class Holder(val f: (Any) -> String?)
var calls = 0
object Cast : Holder({ value -> calls += 1; value as? String })

class Named : Holder(f = { value -> calls += 1; value as? String }) {
    val marker = 7
}

class Secondary : Holder {
    constructor() : super({ value -> calls += 1; value as? String })
}

class Delegated(f: (Any) -> String?) : Holder(f) {
    constructor() : this({ value -> calls += 1; value as? String })
}

open class TaggedHolder(val marker: Int = 8, val f: (Any) -> String?)
object DefaultCast : TaggedHolder(f = { value -> calls += 1; value as? String })
object ReorderedCast : TaggedHolder(f = { value -> calls += 1; value as? String }, marker = 9)

fun main() {
    println(Cast.f("ok"))
    println(Cast.f(42))
    println(calls)
    val named = Named()
    println(named.f("named"))
    println(named.marker)
    println(Secondary().f("secondary"))
    println(Delegated().f("delegated"))
    println(DefaultCast.f("default"))
    println(DefaultCast.marker)
    println(ReorderedCast.f("reordered"))
    println(ReorderedCast.marker)
    println(calls)
}
