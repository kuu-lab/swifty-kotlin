// KUU-4493: bare generic factories must infer from the compound-assignment
// operator parameter and the containsAll Collection<T> parameter.
class Holder {
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    fun addScope() {
        scopes += mutableMapOf()
    }
}

fun main() {
    val holder = Holder()
    val scopes = ArrayDeque<MutableMap<String, Boolean>>()
    scopes += mutableMapOf()
    holder.scopes += mutableMapOf()
    holder.addScope()
    println(scopes.size)
    println(holder.scopes.size)

    val list = listOf(1, 2, 3, 4, 5)
    println(list.containsAll(emptyList()))
    println(list.containsAll(listOf(1, 2)))
    println(setOf("a", "b").containsAll(emptyList()))
}
