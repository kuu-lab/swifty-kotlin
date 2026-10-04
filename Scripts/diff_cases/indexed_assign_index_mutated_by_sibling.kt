// BUG: a bare mutable-local index/receiver operand in an indexed assign or
// indexed compound assign returns that local's persistent storage register
// by identity rather than a value snapshot. Since KIR instructions execute
// in the order they are appended, a later sibling operand that mutates the
// same register in place (e.g. the value expression containing `i++`/`++i`)
// was observed by the `kk_array_get`/`kk_array_set` (or custom operator
// get/set) call, instead of the index value at the point it was evaluated.
fun main() {
    var i = 0
    val arr = IntArray(4)
    arr[i] = i++
    arr[i] = ++i
    println(arr.toList())
    println(i)

    var j = 0
    val lst = mutableListOf(0, 0, 0, 0)
    lst[j] = j++
    lst[j] = ++j
    println(lst)
    println(j)

    var k = 0
    val arr2 = intArrayOf(100, 200, 300, 400)
    arr2[k] += k++
    println(arr2.toList())
    println(k)

    var m = 0
    val lst2 = mutableListOf(100, 200, 300, 400)
    lst2[m] += 7 + m++
    println(lst2)
    println(m)
}
