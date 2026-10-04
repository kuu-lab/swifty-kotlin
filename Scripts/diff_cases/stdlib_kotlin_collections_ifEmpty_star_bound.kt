fun <C> collectionSize(value: C): Int where C : Collection<*> {
    return value.size
}

fun main() {
    println(collectionSize(listOf("value")))
}
