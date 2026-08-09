// KSP-424: List access functions are provided by bundled Kotlin source
// (ListAccessHOF.kt / ListSearchHOF.kt), not by kk_list_* runtime bridges.
fun main() {
    val list = listOf(10, 20, 30)
    val empty = emptyList<Int>()
    val single = listOf(42)

    println(list.getOrNull(0))
    println(list.getOrNull(2))
    println(list.getOrNull(3))
    println(list.getOrNull(-1))
    println(empty.getOrNull(0))

    println(list.getOrElse(1) { it * 100 })
    println(list.getOrElse(3) { it * 100 })
    println(list.getOrElse(-2) { it * 100 })
    println(empty.getOrElse(0) { -1 })

    println(list.elementAt(1))
    println(list.elementAtOrNull(2))
    println(list.elementAtOrNull(-1))
    println(empty.elementAtOrNull(0))
    println(list.elementAtOrElse(0) { it - 1 })
    println(list.elementAtOrElse(9) { it - 1 })
    println(empty.elementAtOrElse(-1) { it - 1 })

    println(list.first())
    println(list.firstOrNull())
    println(empty.firstOrNull())
    println(list.last())
    println(list.lastOrNull())
    println(empty.lastOrNull())
    println(single.single())
    println(single.singleOrNull())
    println(empty.singleOrNull())
    println(list.singleOrNull())

    try {
        empty.elementAt(0)
    } catch (e: IndexOutOfBoundsException) {
        println("elementAt empty: caught")
    }
    try {
        list.elementAt(-1)
    } catch (e: IndexOutOfBoundsException) {
        println("elementAt negative: caught")
    }
    try {
        empty.first()
    } catch (e: NoSuchElementException) {
        println("first empty: caught")
    }
    try {
        empty.last()
    } catch (e: NoSuchElementException) {
        println("last empty: caught")
    }
    try {
        empty.single()
    } catch (e: NoSuchElementException) {
        println("single empty: caught")
    }
    try {
        list.single()
    } catch (e: IllegalArgumentException) {
        println("single many: caught")
    }
}
