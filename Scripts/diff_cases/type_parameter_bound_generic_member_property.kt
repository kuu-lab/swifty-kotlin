open class Base(val name: String)

class Holder<T>(val value: T, val items: List<T>)

fun <H : Holder<Base>> readValue(holder: H): Base {
    return holder.value
}

fun <H : Holder<Base>, K : H> readChained(holder: K): String {
    return holder.value.name + holder.items.size
}

fun main() {
    val holder = Holder(Base("a"), listOf(Base("b"), Base("c")))
    println(readValue(holder).name)
    println(readChained<Holder<Base>, Holder<Base>>(holder))
}
