// KUU-4458: `x[if (c) a else b] = v` must parse as an indexed `set`, not
// degrade into a val reassignment of the if-branch variable.
fun main() {
    val a = IntArray(3)
    val i = 1
    a[if (i < 0) 0 else i] = 9
    println(a.toList())

    val l = mutableListOf(0, 0, 0)
    l[if (true) 0 else 1] = 7
    println(l)

    // A `<` comparison as the index exercises the same assign-operator scan.
    val m = mutableMapOf<Boolean, Int>()
    m[i < 0] = 3
    println(m)

    a[if (i > 5) 0 else i] += 2
    println(a.toList())
}
