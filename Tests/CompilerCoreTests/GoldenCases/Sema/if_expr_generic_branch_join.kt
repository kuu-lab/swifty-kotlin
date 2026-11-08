// KUU-4472: `if`/`when` branches that are calls with unconstrained type
// arguments are re-solved against the sibling branch's type, keeping the
// join at `MutableList<W>` instead of the `MutableList<out W>` projection.
package golden.sema

class W(val x: Int)

abstract class TB {
    protected abstract fun mk(children: List<W>, top: Boolean): W

    private fun g(b: Boolean, m: MutableList<W>): W {
        val children = if (b) ArrayList() else m
        children.add(W(1))
        return mk(children, b)
    }

    private fun h(b: Boolean, m: MutableList<W>): W {
        val children = if (b) m else ArrayList()
        children.add(W(2))
        return mk(children, b)
    }

    private fun w(b: Boolean, m: MutableList<W>): W {
        val children = when (b) {
            true -> ArrayList()
            else -> m
        }
        children.add(W(3))
        return mk(children, b)
    }
}
