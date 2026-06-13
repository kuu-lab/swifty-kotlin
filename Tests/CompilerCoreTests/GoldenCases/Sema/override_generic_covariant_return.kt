package golden.sema

open class ListProvider<T> {
    open fun items(): List<T> = emptyList()
}

// Valid: List<Int> is a subtype of List<Number> after T := Number.
class IntListProvider : ListProvider<Number>() {
    override fun items(): List<Int> = emptyList()
}

open class NumberHolder<T : Number> {
    open fun value(): T = throw RuntimeException()
}

// Valid: Int is a subtype of Number after T := Int.
class IntHolder : NumberHolder<Int>() {
    override fun value(): Int = 42
}

fun main() {
    val listProvider = IntListProvider()
    val valueHolder = IntHolder()
    println(listProvider.items().size)
    println(valueHolder.value())
}
