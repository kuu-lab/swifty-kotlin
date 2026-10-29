import kotlinx.coroutines.flow.*

@Suppress("UNCHECKED_CAST")
fun main() {
    val value: Any = flowOf(1)
    println(value is Flow<*>)
    println((value as Flow<Int>) is Flow<*>)
    val other: Any = "not a flow"
    println(other is Flow<*>)
    try {
        other as Flow<Int>
        println("bad cast")
    } catch (e: ClassCastException) {
        println("wrong type")
    }
}
