// Kotlin evaluates `b[i] += v` as receiver, index, get, value, op, set.
// Before the fix, KSwiftK evaluated the right-hand side before get().
class Box {
    val d = IntArray(1)
    operator fun get(i: Int): Int { println("get"); return d[i] }
    operator fun set(i: Int, v: Int) { println("set"); d[i] = v }
}

fun idx(): Int { println("index"); return 0 }
fun v(): Int { println("value"); return 1 }

val arr = intArrayOf(10)
fun bump(): Int { arr[0] = 100; return 1 }

fun main() {
    val b = Box(); b[idx()] += v(); println(b.d[0])
    // The array element is read before the right-hand side runs, so the
    // write performed by bump() is overwritten by 10 + 1.
    arr[0] += bump(); println(arr[0])
}
