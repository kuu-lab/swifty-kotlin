class OpenList : AbstractList<Int>() {
    override val size: Int get() = 1
    override fun get(index: Int): Int = 7
    override fun indexOf(element: Int): Int = 101
    override fun lastIndexOf(element: Int): Int = 202
    override fun subList(fromIndex: Int, toIndex: Int): List<Int> = listOf(303)
}

fun probe(abstract: AbstractList<Int>, list: List<Int>) {
    abstract.indexOf(7)
    abstract.lastIndexOf(7)
    abstract.subList(0, 1)
    list.indexOf(7)
    list.lastIndexOf(7)
    list.subList(0, 1)
}
