import Holder as Alias

var initialized = 0
object Holder {
    init { initialized += 1 }
    class Child(val value: Int = 7) {
        fun result(): Int = value
    }
    fun ordinary(): Int = initialized + 40
}
object Outer { object NestedHolder { class Child(val value: Int) } }
class ClassHolder { class Child(val value: Int) }
object EmptyHolder { class Child }
object FactoryHolder {
    class Child(val value: String)
    fun Child(value: Int): Int = value + 20
}
object PrivateFactoryHolder {
    class Child private constructor(val value: Number)
    fun Child(value: Int): Int = value + 30
}
fun result() = EmptyHolder.Child()

fun main() {
    result()
    println(Holder.Child().result())
    println(Holder.Child(11).result())
    println(Alias.Child(13).result())
    println(Outer.NestedHolder.Child(17).value)
    println(ClassHolder.Child(19).value)
    println(initialized)
    println(Holder.ordinary())
    println(initialized)
    println(FactoryHolder.Child(3))
    println(PrivateFactoryHolder.Child(5))
}
