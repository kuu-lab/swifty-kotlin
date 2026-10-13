var events = ""
var getters = 0
class Holder(var seed: Int)
val Holder.callback: () -> Int
    get() { getters++; return { seed } }
val Holder.add: (Int) -> Int
    get() { events += "getter;"; return { value -> seed + value } }
val Holder.action: String.() -> Int
    get() = { seed + length }
val Holder.runCallback: ((Int) -> Int) -> Int
    get() = { transform -> transform(seed) }
class Box<T>(val value: T) {
    val String.read: () -> T get() = { value }
    fun readValue(): T = "".read()
}
class Member {
    val callback: () -> Int = { 20 }
}
val Member.callback: () -> Int get() = { 9 }
class Method {
    fun callback(): Int = 99
}
val Method.callback: () -> Int get() = { 7 }
class Overloaded { fun callback(value: Int): Int = value }
val Overloaded.callback: () -> Int get() = { 7 }
open class Base {
    open val Int.callback: () -> Int get() = { this + 10 }
    fun use(): Int = 2.callback()
}
class Derived : Base() {
    override val Int.callback: () -> Int get() = { this + 20 }
}
interface Provider {
    val Int.callback: () -> Int
    fun use(): Int = 2.callback()
}
class Concrete : Provider {
    override val Int.callback: () -> Int get() = { this + 20 }
}
fun doubled(value: Int): Int = value * 2
fun receiver(): Holder { events += "receiver;"; return Holder(4) }
fun argument(): Int { events += "arg;"; return 5 }
fun main() {
    val holder = Holder(7)
    println(holder.callback())
    holder.seed = 8
    println(holder.callback())
    println("getters:$getters")
    println(receiver().add(argument()))
    println(events)
    println(holder.action("abc"))
    println(holder.runCallback { it * 2 })
    println(holder.runCallback(::doubled))
    println(Box("typed").readValue())
    println(Box(42).readValue())
    println(Member().callback())
    println(Method().callback())
    println(Overloaded().callback())
    println(Derived().use())
    println(Concrete().use())
    val absent: Holder? = null
    events = ""
    println(absent?.add(argument()))
    println("absent:$events")
    val present: Holder? = holder
    println(present?.action("xy"))
    println(present?.callback())
}
