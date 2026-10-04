// `a[i]++` / `++a[i]` in expression position. Before the fix, the operator
// token was silently dropped: `val old = a[0]++` never incremented a[0].
class C(val n: Int) {
    operator fun inc() = C(n + 1)
    operator fun dec() = C(n - 1)
}

class Box {
    val d = IntArray(2)
    operator fun get(i: Int): Int { println("get $i"); return d[i] }
    operator fun set(i: Int, v: Int) { println("set $i $v"); d[i] = v }
}

fun idx(): Int { println("idx"); return 1 }

fun main() {
    val a = intArrayOf(5); val old = a[0]++; println(old); println(a[0])
    val pre = ++a[0]; println(pre); println(a[0])
    val l = mutableListOf(1, 2); println(l[1]--); println(--l[0]); println(l)
    val cs = arrayOf(C(1)); val oc = cs[0]++; println(oc.n); println(cs[0].n); println((--cs[0]).n)
    // get()/set() and the index expression run exactly once.
    val b = Box(); println(b[idx()]++); println(++b[idx()])
    var i = 0; val arr = intArrayOf(10, 20); println(arr[i++]++); println(arr.toList()); println(i)
}
