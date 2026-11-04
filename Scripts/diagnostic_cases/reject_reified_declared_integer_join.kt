// EXPECT-REJECT
// KUU-4160: joins of distinct declared signed integer types infer a
// `Number & Comparable<*>` intersection, which a reified parameter cannot
// take. Literal-driven and unsigned joins stay accepted (no error lines).
fun main() {
    val b: Byte = 1
    val s: Short = 2
    val i: Int = 3
    val l: Long = 4L
    val u: UInt = 3u
    val ub: UByte = 1u
    arrayOf(i, 2L)
    arrayOf(b, s)
    arrayOf(s, i)
    arrayOf(i, l)
    arrayOf(1, 2u)
    arrayOf(b, 200)
    arrayOf(i, 5000000000)
    arrayOf(1, 2L)
    arrayOf(1, i)
    arrayOf(1, l)
    arrayOf(b, 100)
    arrayOf(1, 2uL)
    arrayOf(1u, 2uL)
    arrayOf(1, ub)
    arrayOf(ub, i)
    arrayOf(i, u)
}
