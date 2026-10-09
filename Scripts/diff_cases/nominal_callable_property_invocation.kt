class Holder(val seed: Int)
var getterCount = 0
open class Action(val base: Int) {
    open operator fun invoke(x: Int = 3): Int = base + x
    operator fun invoke(prefix: String, x: Int): String = prefix + (base + x)
}
class DoubleAction(base: Int) : Action(base) {
    override operator fun invoke(x: Int): Int = (base + x) * 2
}
interface Callback { operator fun invoke(x: Int): Int }
class InterfaceAction(val base: Int) : Callback {
    override operator fun invoke(x: Int): Int = base + x
}
val Holder.callback: Action get() { getterCount++; return Action(seed) }
val Holder.virtual: Action get() = DoubleAction(seed)
val Holder.viaInterface: Callback get() = InterfaceAction(seed)
class MemberHolder(val callback: Action)
class GetterHolder(val seed: Int) { val callback: Action get() = Action(seed) }
open class BaseHolder { open val callback: Action get() = Action(1) }
class DerivedHolder : BaseHolder() { override val callback: Action get() = Action(20) }
interface PropertyHolder { val callback: Action }
class PropertyImpl : PropertyHolder { override val callback: Action get() = Action(30) }
class GenericAction<T>(val value: T) { operator fun invoke(): T = value }
class GenericOwner<T>(val value: T) { val callback: GenericAction<T> get() = GenericAction(value) }
var sharedAction = Action(1)
val Holder.shared: Action get() = sharedAction
fun replaceAction(): Int { sharedAction = Action(100); return 2 }
fun receiver(): Holder { println("receiver"); return Holder(10) }
val Holder.ordered: Action get() { println("getter"); return Action(seed) }
fun argument(): Int { println("argument"); return 2 }
class VariadicAction(val base: Int) {
    operator fun invoke(vararg values: Int): Int {
        var total = base
        for (value in values) total += value
        return total
    }
}
val Holder.variadic: VariadicAction get() = VariadicAction(seed)
class ExtensionScopeOwner(val seed: Int)
class BlockAction(val seed: Int) {
    operator fun invoke(block: ExtensionScopeOwner.() -> Unit): Int {
        ExtensionScopeOwner(seed).block()
        return 42
    }
}
val ExtensionScopeOwner.apply: BlockAction get() = BlockAction(seed)
class MemberScopeOwner(val seed: Int) { val apply: BlockAction get() = BlockAction(seed) }
val Holder.throwing: Action get() { println("throwing-getter"); throw IllegalStateException("getter") }
fun failingArgument(): Int { println("throwing-argument"); throw IllegalStateException("argument") }
class ThrowingAction { operator fun invoke(): Int = throw IllegalArgumentException("invoke") }
val Holder.failure: ThrowingAction get() = ThrowingAction()
class PairAction { operator fun invoke(a: Int, b: Int): Int = a * 10 + b }
val Holder.pair: PairAction get() = PairAction()
fun main() {
    println(Holder(10).callback(2))
    println("getters:" + getterCount)
    println(Holder(10).callback())
    println(Holder(10).callback(x = 4))
    println(Holder(10).callback(prefix = "sum:", x = 5))
    println(Holder(10).virtual(2))
    println(Holder(10).virtual())
    println(Holder(10).viaInterface(3))
    println(MemberHolder(Action(4)).callback(2))
    println(GetterHolder(5).callback(2))
    val base: BaseHolder = DerivedHolder()
    println(base.callback(2))
    val iface: PropertyHolder = PropertyImpl()
    println(iface.callback(2))
    println(GenericOwner("generic").callback())
    val absent: Holder? = null
    println(absent?.callback(argument()))
    println("getters:" + getterCount)
    val present: Holder? = Holder(6)
    println(present?.callback(2))
    println("getters:" + getterCount)
    println(Holder(0).shared(replaceAction()))
    println(receiver().ordered(argument()))
    println(Holder(10).variadic(1, 2, 3))
    println(Holder(10).variadic(*intArrayOf(4, 5)))
    println(ExtensionScopeOwner(8).apply { println(seed) })
    fun MemberScopeOwner.apply(block: ExtensionScopeOwner.() -> Unit): Int = 99
    println(MemberScopeOwner(9).apply { println(seed) })
    try { Holder(10).throwing(argument()) } catch (e: IllegalStateException) { println(e.message) }
    try { Holder(10).callback(failingArgument()) } catch (e: IllegalStateException) { println(e.message) }
    println("getters:" + getterCount)
    try { Holder(10).failure() } catch (e: IllegalArgumentException) { println(e.message) }
    var first = 1
    fun mutate(): Int { first = 9; return 2 }
    println(Holder(10).pair(first, mutate()))
}
