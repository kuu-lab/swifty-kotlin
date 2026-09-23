// KUU-629: MutableList.set/add(index, element)/addAll(index, collection) must
// throw IndexOutOfBoundsException for an out-of-range index, not a raw Throwable.
fun main() {
    val l = mutableListOf(1, 2)
    try {
        l[5] = 9
        println("set-missing")
    } catch (e: IndexOutOfBoundsException) {
        println("set-ioobe")
    } catch (e: Exception) {
        println("set-other")
    }

    try {
        l.add(5, 9)
        println("add-missing")
    } catch (e: IndexOutOfBoundsException) {
        println("add-ioobe")
    } catch (e: Exception) {
        println("add-other")
    }

    try {
        l.addAll(5, listOf(9))
        println("addAll-missing")
    } catch (e: IndexOutOfBoundsException) {
        println("addAll-ioobe")
    } catch (e: Exception) {
        println("addAll-other")
    }

    try {
        l[-1] = 9
        println("set-neg-missing")
    } catch (e: IndexOutOfBoundsException) {
        println("set-neg-ioobe")
    }

    // In-bounds indexed mutation still succeeds.
    l[0] = 7
    l.add(1, 8)
    l.addAll(2, listOf(9))
    println(l)
}
