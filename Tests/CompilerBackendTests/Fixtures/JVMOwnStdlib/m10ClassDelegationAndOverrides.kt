interface Counter { var value: Int; fun next(step: Int = 1): Int; fun twice(): Int = next(2) }
class Store(override var value: Int): Counter { override fun next(step: Int): Int { value += step; return value } }
class Forward(var target: Counter): Counter by target
class Override(target: Counter): Counter by target { override fun next(step: Int): Int = step * 10 }
object Global: Counter by Store(20)
class AnonymousDelegate: Counter by (object: Counter by Store(50) {}) { fun read(): Int = value }
fun main() {
    val store = Store(10)
    val forward = Forward(store)
    println(forward.next()); forward.value = 30; println(store.value)
    forward.target = Store(100)
    println(forward.twice()); println(forward.value)
    val override = Override(store)
    println(override.next(3)); println(override.twice())
    println(Global.next())
    val anonymous: Counter = object: Counter by Store(40) {}
    println(anonymous.next())
    val captured: Counter = object: Counter by store {}
    println(captured.next()); println(AnonymousDelegate().read())
}
