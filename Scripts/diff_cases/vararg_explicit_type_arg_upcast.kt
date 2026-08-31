// Regression for a type-inference bug found while investigating KSP-Map-iterator
// CI failures (PR #6224): an explicit type argument on a call whose vararg
// parameter type contains the same type variable in a covariant (`out`)
// position must be treated as authoritative, not folded into the same
// lub/glb bound pool as the vararg elements' own (upcast-compatible) types.
//
// `mapOf<Any?, Number?>("a" to 1, null to null)` passes Pair<String, Int> and
// Pair<Nothing?, Nothing?> where Pair<Any?, Number?> is expected. Both upcast
// fine on their own, but kswiftc's constraint solver used to compute the
// lower-bound candidate for V as lub(Number?, Int, Nothing?), and its lub()
// widens any non-identical, non-KClass combination straight to `Any?`
// instead of recognizing `Int <: Number`  -  producing a bogus
// "Conflicting bounds for type variable" error even though every individual
// bound is satisfied by the explicit Number? argument.
fun main() {
    val projected: Map<Any?, Number?> = mapOf<Any?, Number?>("a" to 1, null to null)
    println(projected)

    val numbers: List<Number> = listOf<Number>(1, 2L, 3.0)
    println(numbers)

    val mixed: Map<Any, Any?> = mapOf<Any, Any?>(1 to "one", 2 to null)
    println(mixed)
}
