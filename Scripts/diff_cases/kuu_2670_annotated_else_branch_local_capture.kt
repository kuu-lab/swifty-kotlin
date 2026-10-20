fun f(list: List<Any>): MutableList<Any> {
    val out = mutableListOf<Any>()
    fun walk(l: List<Any>) {
        for (e in l) {
            if (e !is List<*>)
                out.add(e)
            else
                @Suppress("UNCHECKED_CAST")
                walk(e as List<Any>)
        }
    }
    walk(list)
    return out
}

fun main() {
    println(f(listOf(listOf(1, 2) as Any, 3)))
}
