import kotlin.reflect.KParameter

fun f(x: Int, y: String) {}
fun g(x: Int, y: String) {}

class C(val v: Int) {
    fun m(a: Int) {}
}

fun String.extfun(a: Int) {}

fun main() {
    // Value equality across separately obtained handles (KUU-4069).
    val p = ::f.parameters[0]
    println("eq: ${p == ::f.parameters[0]}")
    println("eq first: ${p == ::f.parameters.first()}")
    println("refeq: ${p === ::f.parameters[0]}")
    println("neq idx: ${p == ::f.parameters[1]}")
    println("neq callable: ${p == ::g.parameters[0]}")
    println("hash consistent: ${p.hashCode() == ::f.parameters[0].hashCode()}")
    println("member equals: ${p.equals(::f.parameters[0])}")
    val anyP: Any = p
    println("eq other: ${anyP == "x"}")
    // JVM-shaped toString per KParameter.Kind.
    for (q in ::f.parameters) println("tostr: $q")
    for (q in C::m.parameters) println("tostr: $q")
    for (q in String::extfun.parameters) println("tostr: $q")
    for (q in ::C.parameters) println("tostr: $q")
    for (q in C::v.parameters) println("tostr: $q")
    // Collection lookup keyed by a fresh, value-equal KParameter.
    val lookup = mapOf(::f.parameters[0] to "ZERO", ::f.parameters[1] to "ONE")
    println("lookup: ${lookup[::f.parameters.first()]}")
    val dedup = setOf(::f.parameters[0], ::f.parameters.first(), ::f.parameters[1])
    println("set size: ${dedup.size}")
    println("set contains: ${dedup.contains(::f.parameters[0])}")
    // callBy accepts separately obtained equivalent keys.
    ::f.callBy(mapOf(::f.parameters[0] to 42, ::f.parameters[1] to "hi"))
    println("callBy ok")
    // Bound references keep their captured receiver in the equality.
    val c1 = C(1)
    val c2 = C(2)
    println("bound eq: ${c1::m.parameters[0] == c1::m.parameters[0]}")
    println("bound neq recv: ${c1::m.parameters[0] == c2::m.parameters[0]}")
    println("bound neq unbound: ${c1::m.parameters[0] == C::m.parameters[1]}")
    println("bound hash: ${c1::m.parameters[0].hashCode() == c1::m.parameters[0].hashCode()}")
    for (q in c1::m.parameters) println("tostr: $q")
    c1::m.callBy(mapOf(c1::m.parameters[0] to 7))
    println("bound callBy ok")
}
