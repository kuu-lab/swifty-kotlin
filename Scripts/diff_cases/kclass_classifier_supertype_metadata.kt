// KUU-1448: A KClass handle synthesized by KType.classifier must expose its
// own supertypes even when that ancestor class's `T::class` literal was never
// evaluated. `Root::class`/`IfaceA::class`/`IfaceB::class` never appear below.
import kotlin.reflect.KClass
import kotlin.reflect.KType

open class Root
open class Middle : Root()
class Leaf : Middle()

interface IfaceA
interface IfaceB : IfaceA
class Impl : IfaceB

fun KType.namedClassifier(name: String): KClass<*>? =
    (classifier as? KClass<*>)?.takeIf { it.simpleName == name }

fun main() {
    val mid = Leaf::class.supertypes.mapNotNull { it.namedClassifier("Middle") }.single()
    println("inherited=${mid.simpleName} inheritedSupertypes=${mid.supertypes.size}")
    val root = mid.supertypes.mapNotNull { it.namedClassifier("Root") }.single()
    println("root=${root.simpleName} rootSupertypes=${root.supertypes.size}")

    println("implSupers=${Impl::class.supertypes}")
    val ifaceB = Impl::class.supertypes.mapNotNull { it.namedClassifier("IfaceB") }.single()
    println("ifaceB=${ifaceB.simpleName} ifaceBSupertypes=${ifaceB.supertypes}")
}
