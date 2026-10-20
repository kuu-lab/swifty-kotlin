interface Source<T> { suspend fun get(value: T): T }
open class Base : Source<Int> { override suspend fun get(value: Int): Int = value + 1 }
class Derived : Base() { override suspend fun get(value: Int): Int = super.get(value) + 1 }
fun main(value: Int): Int = value
suspend fun twice(value: Int): Int = value * 2
suspend fun main() {
    val source: Source<Int> = Derived()
    println(source.get(40))
    val operation: suspend Int.(Int) -> Int = { other -> twice(this) + other }
    println(operation(20, 2))
    val callback: suspend () -> Int = { twice(21) }
    println(callback())
    println(main(7))
}
