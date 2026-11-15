// DIFF_JVM
// KUU-4585: a function that instantiates a class declared *after* it and
// returns it through an interface type used to register the class's itable
// entries with the raw implementation symbol while the member bodies were not
// lowered yet. Methods needing ABI adaptation (e.g. `next(): String` via the
// flat String aggregate) were then invoked with the wrong ABI and produced
// null/garbage or crashed in field access. `CharSequence.lines()` relied on
// this shape (LinesSequence.iterator() returning a later-declared
// LinesIterator) and was broken by it.

fun makeIter(): Iterator<String> = ForwardIter()

fun makeCounted(): Counter = ForwardCounter(3)

private class ForwardIter : Iterator<String> {
    private var i = 0
    override fun hasNext(): Boolean = i < 2
    override fun next(): String {
        i++
        return "x" + i
    }
}

private interface Counter {
    fun count(): Int
    fun label(): String
}

private class ForwardCounter(private var n: Int) : Counter {
    override fun count(): Int = n
    override fun label(): String = "n=" + n
}

fun main() {
    val it = makeIter()
    while (it.hasNext()) println("got=" + it.next())
    val c = makeCounted()
    println("count=" + c.count() + ",label=" + c.label())
}
