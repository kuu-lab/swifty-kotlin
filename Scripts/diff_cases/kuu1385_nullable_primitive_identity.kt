const val C = "cd"
val plainVal = "ab"
object O { const val OC = "oc" }
class Holder(val p: Int?) {
    var mp: Int? = 5
}
fun param5(p: Int?): Boolean = p === (5 as Int?)
fun freshBox(): Any = 200
fun freshBox5(): Any = 5
fun main() {
    // Nullable primitive `===` is JVM reference identity on the boxed value:
    // out-of-cache-range independently boxed values are distinct.
    val i1: Int? = 128
    val i2: Int? = 128
    println(i1 === i2)
    val l1: Long? = 128L
    val l2: Long? = 128L
    println(l1 === l2)
    val s1: Short? = 128
    val s2: Short? = 128
    println(s1 === s2)
    val c1: Char? = 'Ā'
    val c2: Char? = 'Ā'
    println(c1 === c2)
    val n1: Int? = -129
    val n2: Int? = -129
    println(n1 === n2)
    val d1: Double? = 1.5
    val d2: Double? = 1.5
    println(d1 === d2)
    val f1: Float? = 1.5f
    val f2: Float? = 1.5f
    println(f1 === f2)
    // Inside the JVM cache ranges the shared box is observed.
    val a: Int? = 5
    val b: Int? = 5
    println(a === b)
    val by1: Byte? = 5
    val by2: Byte? = 5
    println(by1 === by2)
    val ch1: Char? = 'z'
    val ch2: Char? = 'z'
    println(ch1 === ch2)
    val t1: Boolean? = true
    val t2: Boolean? = true
    println(t1 === t2)
    val e1: Int? = 127
    val e2: Int? = 127
    println(e1 === e2)
    val m1: Int? = -128
    val m2: Int? = -128
    println(m1 === m2)
    // Copies and parameters alias the same box.
    val copy = a
    println(a === copy)
    println(param5(a))
    println(param5(200))
    println(freshBox() === freshBox())
    println(freshBox5() === freshBox5())
    // Any-erased values share the same cache.
    val any5a: Any = 5
    val any5b: Any = 5
    println(any5a === any5b)
    println(any5a === a)
    val i: Int = 5
    println(a === i)
    println(i === a)
    // null identity and non-null primitive value identity stay intact.
    val z1: Int? = null
    val z2: Int? = null
    println(z1 === z2)
    val x: Int = 128
    val y: Int = 128
    println(x === y)
    println(a === null)
    println(z1 === a)
    // A statically non-null operand compared to null is a tautology even
    // when it was smart-cast from a nullable slot (the raw bits may alias
    // the null sentinel — Long.MIN_VALUE / -0.0).
    println(i != null)
    println(i == null)
    var sv: Long? = 1L
    sv = Long.MIN_VALUE
    println(sv != null)
    println(sv == null)
    var sd: Double? = 1.0
    sd = -0.0
    println(sd != null)
    // Structural equality is unchanged.
    println(i1 == i2)
    println(a == 5)
    println(a == 200)
    println(a === b)
    println(a !== b)
    println(i1 !== i2)
    // Property slots hold the same box representation.
    val h1 = Holder(5)
    val h2 = Holder(5)
    println(h1.p === h2.p)
    println(h1.mp === h2.mp)
    // Sentinel-colliding values keep working.
    val longMin: Long? = Long.MIN_VALUE
    val longMin2: Long? = Long.MIN_VALUE
    println(longMin === longMin2)
    println(longMin == longMin2)
    println(longMin == null)
    val negZero: Double? = -0.0
    println(negZero == null)
    println(negZero === negZero)
    // Compile-time constant concatenation interns to the literal.
    println("ab" + "c" === "abc")
    println("a" + 'b' === "ab")
    println("a" + 5 === "a5")
    println("a" + true === "atrue")
    println("" + null === "null")
    println("x" + "y" + "z" === "xyz")
    println("a" + 1.5 === "a1.5")
    println("a" + 1.5f === "a1.5")
    println("x" + C === "xcd")
    println("x" + O.OC === "xoc")
    println("p" + "${5}" === "p5")
    val dyn = "ab" + "c"
    println(dyn === "abc")
    // Runtime concatenation is not interned.
    val rt = "ab"
    println(rt + "c" === "abc")
    println("x" + plainVal === "xab")
    var v = "ab"
    println("x" + v === "xab")
    println("intern" === "intern")
}
