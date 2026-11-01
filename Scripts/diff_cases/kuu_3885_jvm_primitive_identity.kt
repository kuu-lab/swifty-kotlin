// DIFF_JVM
// KUU-3885: `===`/`!==` with exactly one primitive operand boxes it through
// its valueOf factory and compares references; two non-null primitives keep
// value equality.
fun <T> compareT(t: T, d: Double): Boolean = t === d
fun freshBox(): Any = 200
fun freshBox5(): Any = 5
fun main() {
    // Reference vs primitive: the primitive boxes via valueOf for if_acmp.
    val x: Any = -0.0
    println(x === -0.0)
    val any5: Any = 5
    println(any5 === 5)
    val any200: Any = 200
    println(any200 === 200)
    val anyT: Any = true
    println(anyT === true)
    val anyC: Any = 'z'
    println(anyC === 'z')
    val anyL: Any = 5L
    println(anyL === 5L)
    val anyF: Any = 1.5f
    println(anyF === 1.5f)
    val b5: Byte = 5
    val anyB: Any = b5
    println(anyB === b5)
    val s5: Short = 5
    val anyS: Any = s5
    println(anyS === s5)
    // Nullable primitive vs primitive.
    val n5: Int? = 5
    println(n5 === 5)
    println(5 === n5)
    val n200: Int? = 200
    println(n200 === 200)
    val i: Int = 5
    println(n5 === i)
    println(i === n5)
    println(freshBox() === freshBox())
    println(freshBox5() === freshBox5())
    // Primitive vs null.
    println(i === null)
    println(i !== null)
    val nNull: Int? = null
    println(nNull === i)
    val aNull: Any? = null
    println(aNull === 5)
    // Two non-null primitives keep value equality.
    val a: Int = 1000
    val b: Int = 1000
    println(a === b)
    println(a !== b)
    val d1: Double = 1.5
    val d2: Double = 1.5
    println(d1 === d2)
    val nan: Double = Double.NaN
    println(nan === nan)
    val l1: Long = 5L
    val l2: Long = 5L
    println(l1 === l2)
    val t1: Boolean = true
    val t2: Boolean = true
    println(t1 === t2)
    val c1: Char = 'x'
    val c2: Char = 'x'
    println(c1 === c2)
    val by1: Byte = 7
    val by2: Byte = 7
    println(by1 === by2)
    println(i === i)
    val neg: Double = -0.0
    println(neg === neg)
    // A type parameter facing a primitive keeps reference identity.
    println(compareT(7.0, 7.0))
    println(compareT("x", 7.0))
}
