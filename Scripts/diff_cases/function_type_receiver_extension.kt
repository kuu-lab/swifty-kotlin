// BUG-C: extension functions whose RECEIVER is itself a function type.
// `fun (Type).name()` was misparsed: KotlinParser+Declarations.swift's
// parseFunctionDeclaration required an identifier-like name right after
// `fun`, so `fun ((Int) -> Int).applyTwice(...)` consumed the receiver's `(`
// as the value-parameter list instead, leaving `this` unresolved inside the
// body (KSWIFTK-SEMA-0051) and the receiver's real parameter list mangled.
//
// Nested-call-argument-position receivers (e.g.
// `println({ x: Int -> x + 1 }.applyTwice(5))`, taking a bare lambda
// literal receiver directly as an outer call's argument) and multi-level
// generic inference through a chained infix call on such a receiver
// (`a then b then c` with implicit lambda parameters) surface separate,
// deeper Sema/KIR gaps unrelated to parsing — tracked separately, not
// exercised here. This case sticks to receivers bound to a named value,
// which already exercises the parser fix end-to-end.
infix fun <A, B, C> ((A) -> B).then(g: (B) -> C): (A) -> C = { g(this(it)) }
fun ((Int) -> Int).applyTwice(x: Int): Int = this(this(x))

fun main() {
    val double: (Int) -> Int = { it * 2 }
    val increment: (Int) -> Int = { it + 1 }
    val combined = double then increment
    println(combined(3))

    val doubler: (Int) -> Int = { x -> x + 1 }
    println(doubler.applyTwice(5))
}
