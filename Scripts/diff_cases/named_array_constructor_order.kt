interface NamedArrayGetter<T> { fun get(): T }
fun namedArrayGetter() = object: NamedArrayGetter<Int> {
    override fun get(): Int = 42
}
fun namedArraySize(): Int { println("size"); return 3 }
fun main() {
    val values = IntArray(init = { it + 1 }, size = namedArraySize())
    println(values[0])
    println(values[2])
    println(namedArrayGetter().get())
}
