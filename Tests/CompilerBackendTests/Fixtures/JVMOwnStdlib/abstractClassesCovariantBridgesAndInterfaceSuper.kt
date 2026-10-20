open class Item { open fun number(): Int = 1 }
class ChildItem: Item() { override fun number(): Int = 2 }
interface Factory { fun create(): Item; val current: Item }
abstract class AbstractFactory: Factory {
    abstract override fun create(): ChildItem
    abstract override val current: ChildItem
}
class Maker: AbstractFactory() {
    override fun create(): ChildItem = ChildItem()
    override val current: ChildItem get() = ChildItem()
}
open class InheritedFactoryBase {
    fun create(): ChildItem = ChildItem()
    val current: ChildItem = ChildItem()
}
class InheritedMaker: InheritedFactoryBase(), Factory
interface A { val amount: Int get() = 3; fun score(): Int = 4 }
interface B: A
class C: B {
    override val amount: Int get() = super<B>.amount + 1
    override fun score(): Int = super<B>.score() + 1
}
fun main() {
    val factory: Factory = Maker()
    println(factory.create().number())
    println(factory.current.number())
    val abstractFactory: AbstractFactory = Maker()
    println(abstractFactory.create().number())
    val c: A = C()
    println(c.amount)
    println(c.score())
    val inherited: Factory = InheritedMaker()
    println(inherited.create().number())
    println(inherited.current.number())
}
