fun <T, C : MutableCollection<T>> appendOne(destination: C, value: T): C {
    destination.add(value)
    return destination
}

fun main() {
    val dest: MutableList<Int> = appendOne(mutableListOf(), 1)
    println(dest)
}
