// KUU-3861: `===`/`!==` across the boxing boundary is JVM reference identity —
// the primitive operand is boxed (Double/Float/unsigned kinds always fresh,
// Int/Long/Byte/Short/Boolean/Char through the JVM identity cache) instead of
// unboxing the reference operand to raw bits.
fun <T> genericIdentity(t: T, d: Double): Boolean = t === d

fun main() {
    // Uncached kinds: distinct boxes of the same value are never identical.
    val x: Any = -0.0
    println(x === -0.0)
    val y: Any = -0.0
    println(x === y)
    println(x !== -0.0)
    val f: Any = 1.5f
    println(f === 1.5f)
    val d: Double = -0.0
    println(d === x)
    // Null never aliases a box — the -0.0 bit pattern equals the raw null
    // sentinel, so comparing raw words used to report true here.
    val nn: Any? = null
    println(nn === -0.0)
    // JVM-cached kinds: in-range values converge on the shared box.
    val i5: Any = 5
    println(i5 === 5)
    println(5 === i5)
    val i: Int = 5
    println(i5 === i)
    println(i === i5)
    val l128: Any = 128L
    println(l128 === 128L)
    val b: Any = true
    println(b === true)
    val c: Any = 'a'
    println(c === 'a')
    // Out-of-cache-range values stay distinct.
    val i1000: Any = 1000
    println(i1000 === 1000)
    val l129: Any = 129L
    println(l129 === 129L)
    val cBig: Any = 'Ā'
    println(cBig === 'Ā')
    // Nullable-primitive and reference peers keep the same identity rules.
    val nd: Double? = -0.0
    println(x === nd)
    val ni: Int? = 5
    println(i5 === ni)
    println(ni === i5)
    val niNull: Int? = null
    println(nn === niNull)
    // Erased generic and non-Any reference supertypes box the primitive too.
    println(genericIdentity(-0.0, -0.0))
    val n: Number = 5
    println(n === 5)
}
