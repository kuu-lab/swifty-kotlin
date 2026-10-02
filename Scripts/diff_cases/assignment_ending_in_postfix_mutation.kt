fun main() {
    // BUG: an assignment statement whose LAST token is `++`/`--` was
    // mis-parsed as a standalone `<expr>++` mutation on a prefix of the
    // statement's tokens, silently discarding everything after that prefix
    // (including the real `=`/compound-assign and its right-hand side).
    var c = 0
    val arr = IntArray(3)
    arr[c++] = c++
    println(arr.toList())
    println(c)

    var z = 1
    z = z++ + z++
    println(z)

    var total = 0
    var n = 5
    total = total + n++
    println(total)

    var w = 10
    val a2 = intArrayOf(1, 2, 3)
    a2[--w % 3] += w++
    println(a2.toList())
    println(w)

    var d = 0
    val lst = mutableListOf(0, 0, 0)
    lst[d++] = d++
    println(lst)
    println(d)
}
