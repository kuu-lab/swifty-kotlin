@JvmInline
value class N(val x: Int?)

@JvmInline
value class S(val x: String)

fun main() {
    // Casting a value class to its own type (nullable or not) must be a
    // no-op: the unboxed payload carries no nominal tag for kk_op_cast to
    // verify, so the nominal check is resolved statically at lowering.
    val n1: N? = N(7)
    println(N(7) as N?)
    println(N(7) as N)
    println(n1 as N?)
    println(n1 as N)
    println(N(7) as N? == n1)

    // Safe casts keep their null contract.
    println(n1 as? N)
    println(n1 as? N?)
    println(N(7) as? N?)
    val nn: N? = null
    println(nn as? N)
    println(nn as? N?)
    println(null as? N)

    // `as` to a non-null value class on a null operand never throws —
    // kotlinc checkcasts the box, which always admits null — and the
    // result stays null regardless of the underlying nullability.
    val nnCast: N? = nn as N
    println(nnCast)
    val ns: S? = null
    val nsCast: S? = ns as S
    println(nsCast)

    // Non-null-underlying value class self-casts.
    println(S("s") as S)

    // A null payload is a real instance: it must not collapse into the null
    // `N?` above when it crosses the same self-cast.
    val np: N? = N(null)
    println(np as N)
    val npCast: N? = np as N
    println(npCast)
    println(N(null) as N?)
    println(npCast == null)
    println(nnCast == null)

    // The `v? as V` result still behaves as a `V`.
    println((n1 as N).x)
    println(payloadOf(n1 as N))
    println(payloadOf(np as N))
}

fun payloadOf(n: N): Int? = n.x
