// `receiver.field += x` where `field: String` and `x` is not itself a String
// must convert `x` the same way `+`/string-template concatenation does
// (Kotlin's `String.plus(other: Any?)` calls `x.toString()`), before handing
// both operands to kk_string_concat_flat -- which assumes both arguments are
// already flat String aggregates. Before the fix, lowerMemberCompoundAssignExpr
// (CallLowerer+MemberAssignment.swift) skipped this conversion entirely and
// fed kk_string_concat_flat the raw, un-stringified value: a class instance
// silently vanished from the result (`h.s += Foo(1)` dropped the `Foo(1)`
// part entirely) and a primitive value (Int/Boolean/...) crashed the process
// outright (kk_string_concat_flat reading an unboxed scalar as a String
// aggregate's pointer/length/hash fields).
//
// A bare local-variable compound assign (`s += x`) and the equivalent
// non-compound form (`h.s = h.s + x`) were unaffected -- both already routed
// through CallLowerer.emitAnyToStringWithNullGuard -- so this was specific to
// the explicit-receiver member-field compound-assignment lowering path.
class Foo(val x: Int) {
    override fun toString(): String = "Foo(" + x + ")"
}
class Holder(var s: String)

fun main() {
    val h = Holder("start=")
    h.s += Foo(1)
    println(h.s)

    val h2 = Holder("n=")
    h2.s += 42
    println(h2.s)

    val h3 = Holder("b=")
    h3.s += true
    println(h3.s)

    val h4 = Holder("nullable=")
    val nf: Foo? = null
    h4.s += nf
    println(h4.s)

    val h5 = Holder("nullableNonNull=")
    val f2: Foo? = Foo(2)
    h5.s += f2
    println(h5.s)
}
