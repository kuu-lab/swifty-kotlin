open class Parent(val block: () -> Int) { fun result(): Int = block() }
class Child(start: Int): Parent({ start + 1 })
interface Source {
    fun base(): Int
    fun callback(): () -> Int = { base() }
}
class Impl: Source { override fun base(): Int = 11 }
interface Extension<T> { fun T.score(): Int; fun run(value: T): Int = value.score() }
class IntExtension: Extension<Int> { override fun Int.score(): Int = this * 2 }
class Accessor {
    var value: Int = 7
        get() { val read = { val nested = { field }; nested() }; return read() }
        set(value) { val write = { val nested = { field = value }; nested() }; write() }
}
class Owner(private var number: Int) {
    private fun plus(value: Int): Int { number += value; return number }
    val callback: (Int) -> Int = { value -> plus(value) }
    fun action(): () -> Int = { number += 1; number }
}
fun main() {
    println(Child(41).result())
    println(Impl().callback()())
    val owner = Owner(10)
    println(owner.callback(2))
    println(owner.action()())
    val accessor = Accessor()
    println(accessor.value)
    accessor.value = 9
    println(accessor.value)
    val extension: Extension<Int> = IntExtension()
    println(extension.run(21))
}
