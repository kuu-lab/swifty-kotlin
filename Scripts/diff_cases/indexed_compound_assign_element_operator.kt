// `a[i] op= v` / `a[i]++` must apply the *element's* own operator
// (`plus`, `plusAssign`, `inc`, ...) to the `get()` result, not the builtin
// numeric arithmetic. Before the fix, `a[0] += V(2)` on an Array<V> panicked
// in kk_array_get_inbounds, and `plusAssign` / `inc` elements were rejected
// with KSWIFTK-TYPE-0001.
data class V(val x: Int) {
    operator fun plus(o: V) = V(x + o.x)
    operator fun minus(o: V) = V(x - o.x)
    operator fun times(k: Int) = V(x * k)
    operator fun inc() = V(x + 1)
    operator fun dec() = V(x - 1)
}

class Acc {
    var s = 0
    operator fun plusAssign(n: Int) { s += n }
    operator fun minusAssign(n: Int) { s -= n }
}

class C(val n: Int) { operator fun inc() = C(n + 1) }

// get()-only receiver: an in-place `plusAssign` needs no set().
class Holder {
    val items = listOf(Acc(), Acc())
    operator fun get(i: Int): Acc {
        println("hget $i")
        return items[i]
    }
}

class Grid {
    private val d = arrayOf(V(0), V(0))
    operator fun get(i: Int): V {
        println("gget $i")
        return d[i]
    }
    operator fun set(i: Int, v: V) {
        println("gset $i $v")
        d[i] = v
    }
}

fun main() {
    val a = arrayOf(V(1)); a[0] += V(2); println(a[0])
    val l = mutableListOf(V(1)); l[0] += V(5); println(l[0])

    val acc = arrayOf(Acc()); acc[0] += 5; println(acc[0].s)
    val accs = mutableListOf(Acc()); accs[0] += 7; accs[0] -= 2; println(accs[0].s)

    val cs = arrayOf(C(1)); cs[0]++; println(cs[0].n)

    val vs = arrayOf(V(10), V(20))
    vs[0] -= V(3); vs[1] *= 2; println(vs.toList())
    vs[0]++; --vs[1]; ++vs[0]; vs[1]--; println(vs.toList())
    l[0]++; l[0]--; l[0]--; println(l)

    val h = Holder(); h[1] += 3; println(h.items[1].s)
    val g = Grid(); g[0] += V(5); g[1]++; println(g[0]); println(g[1])

    // Builtin element types keep the builtin arithmetic.
    val ints = arrayOf(1, 2); ints[0] += 5; ints[1]++; println(ints.toList())
    val strs = mutableListOf("a"); strs[0] += "b"; println(strs)
    val ia = intArrayOf(3); ia[0] *= 4; ia[0]--; println(ia[0])
    val ds = arrayOf(1.5); ds[0] += 1.0; println(ds[0])
}
