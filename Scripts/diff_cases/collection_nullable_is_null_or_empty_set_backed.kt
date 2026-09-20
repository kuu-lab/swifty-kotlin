// KUU-543: `isNullOrEmpty()` on a Collection<T>?/MutableCollection<T>? receiver
// must not use the List-only kk_list_is_empty bridge — it returns true for any
// non-list box, so a Set-backed receiver would report empty even when it is
// not. The bare-interface kinds need the type-tag dispatching
// __kk_collection_isEmpty bridge instead.
fun main() {
    val c: Collection<Int>? = setOf(1, 2, 3)
    println(c.isNullOrEmpty())
    val emptyC: Collection<Int>? = emptySet()
    println(emptyC.isNullOrEmpty())
    val nullC: Collection<Int>? = null
    println(nullC.isNullOrEmpty())
    val listC: Collection<Int>? = listOf(1)
    println(listC.isNullOrEmpty())

    val mc: MutableCollection<Int>? = mutableSetOf(4, 5)
    println(mc.isNullOrEmpty())
    val nullMc: MutableCollection<Int>? = null
    println(nullMc.isNullOrEmpty())

    val s: Set<Int>? = setOf(7)
    println(s.isNullOrEmpty())
    val l: List<Int>? = listOf(8)
    println(l.isNullOrEmpty())
}
