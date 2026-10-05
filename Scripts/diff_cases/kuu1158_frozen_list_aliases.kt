fun addList(target: MutableList<String>) { target.add("c") }
fun removeList(target: MutableList<String>) { target.remove("a") }
fun clearList(target: MutableList<String>) { target.clear() }
fun addCollection(target: MutableCollection<String>) { target.add("c") }
fun removeCollection(target: MutableCollection<String>) { target.remove("a") }
fun clearCollection(target: MutableCollection<String>) { target.clear() }
fun setList(target: MutableList<String>) { target.set(0, "c") }

fun probe(path: Int) {
    var alias: MutableList<String> = mutableListOf()
    var view: MutableList<String> = alias
    var iterator: MutableIterator<String> = alias.iterator()
    val built = buildList<String> {
        add("a")
        add("b")
        alias = this
        view = subList(0, 1)
        iterator = this.iterator()
        iterator.next()
    }
    println(path)
    try {
        when (path) {
            0 -> addList(alias)
            1 -> removeList(alias)
            2 -> clearList(alias)
            3 -> addCollection(alias)
            4 -> removeCollection(alias)
            5 -> clearCollection(alias)
            6 -> iterator.remove()
            7 -> clearList(view)
            8 -> setList(view)
        }
        println("accepted")
    } catch (e: IllegalStateException) {
        println("wrong exception")
    } catch (e: UnsupportedOperationException) {
        println("rejected")
    }
    println(built.size)
    println(built[0])
    println(built[1])
}

fun main() {
    for (path in 0..8) probe(path)
    val mutable = mutableListOf("a", "b")
    addList(mutable)
    removeCollection(mutable)
    setList(mutable)
    println(mutable)
    clearList(mutable)
    println(mutable.size)
}
