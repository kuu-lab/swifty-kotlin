// KUU-4472: an if/when branch that is a call with unconstrained type
// arguments (`ArrayList()` → `ArrayList<Any>` by default) must be re-solved
// against the sibling branch's type, like kotlinc's single constraint
// system, so the join stays `MutableList<W>` instead of the use-site
// projection `MutableList<out W>` (which hides `in`-position members like
// `add`).

class W(val x: Int)

fun size(l: List<W>): Int = l.size

fun main() {
    val m = mutableListOf(W(9))

    val c1 = if (true) ArrayList() else m
    c1.add(W(1))
    println(size(c1))

    val c2 = if (false) m else ArrayList()
    c2.add(W(2))
    println(size(c2))

    val c3 = if (true) ArrayList<W>() else m
    c3.add(W(3))
    println(size(c3))

    val c4 = if (true) java.util.LinkedList<W>() else m
    c4.add(W(4))
    println(size(c4))

    val c5 = when (true) {
        true -> ArrayList()
        else -> m
    }
    c5.add(W(5))
    println(size(c5))

    val c6 = when {
        false -> m
        else -> ArrayList()
    }
    c6.add(W(6))
    println(size(c6))
}
