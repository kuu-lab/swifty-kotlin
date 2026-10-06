import kotlin.reflect.KClass
import kotlin.reflect.typeOf

class Plain
open class Open
abstract class Abstract
interface Iface
fun interface FunIface { fun run() }
data class Data(val value: Int)
sealed class Empty
sealed class Root
open class Child : Root()
class Grandchild : Child()
object Leaf : Root()
sealed interface SealedIface
class Impl : SealedIface
var initialized = 0
object Obj {
    init { initialized += 1 }
    val value = 42
}
class Owner { companion object { val value = 7 } }

fun flags(k: KClass<*>) {
    println(k.isFinal)
    println(k.isOpen)
    println(k.isAbstract)
    println(k.isSealed)
}
fun <T : Any> instance(k: KClass<T>): T? = k.objectInstance
fun main() {
    val classifier = typeOf<Root>().classifier as KClass<*>
    println(classifier.sealedSubclasses.size)
    println(classifier.isSealed)
    flags(Plain::class)
    flags(Data::class)
    flags(Obj::class)
    flags(Open::class)
    flags(Abstract::class)
    flags(Iface::class)
    flags(FunIface::class)
    flags(Empty::class)
    flags(SealedIface::class)
    val erased: KClass<*> = Obj::class
    println(initialized)
    println(erased.objectInstance === Obj)
    println(initialized)
    val nullableClassifier = typeOf<Obj?>().classifier as KClass<*>
    println(nullableClassifier == Obj::class)
    println(nullableClassifier.objectInstance === Obj)
    val typed: Obj? = instance(Obj::class)
    println(typed?.value)
    println(Plain::class.objectInstance == null)
    println(Owner.Companion::class.objectInstance === Owner.Companion)
    println(Owner.Companion::class.objectInstance?.value)
    println(Empty::class.sealedSubclasses.size)
    val subclasses: List<KClass<out Root>> = Root::class.sealedSubclasses
    println(subclasses.size)
    println(subclasses.contains(Child::class))
    println(subclasses.contains(Leaf::class))
    println(subclasses.contains(Grandchild::class))
    println(Root::class.sealedSubclasses.size)
    println(Plain::class.sealedSubclasses.size)
    println(SealedIface::class.sealedSubclasses.contains(Impl::class))
    flags(Plain()::class)
    flags(Open()::class)
}
