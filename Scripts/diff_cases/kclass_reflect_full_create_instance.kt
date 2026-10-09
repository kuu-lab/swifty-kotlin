// KUU-1377: kotlin.reflect.full createInstance / isSubclassOf / isSuperclassOf /
// createType / starProjectedType
import kotlin.reflect.full.*
import kotlin.reflect.KTypeProjection

open class Root
open class Middle : Root()
class Leaf : Middle()
class Other
class Box<T>
class NeedsArg(val x: Int)
class Defaulted(val x: Int = 7) {
    override fun toString(): String = "Defaulted($x)"
}

fun main() {
    println(Defaulted::class.createInstance())
    println(Leaf::class.createInstance() is Leaf)
    try {
        NeedsArg::class.createInstance()
    } catch (e: IllegalArgumentException) {
        println("IAE")
    }

    println(Leaf::class.isSubclassOf(Root::class))
    println(Leaf::class.isSubclassOf(Middle::class))
    println(Leaf::class.isSubclassOf(Leaf::class))
    println(Leaf::class.isSubclassOf(Other::class))
    println(Root::class.isSubclassOf(Leaf::class))
    println(Leaf::class.isSubclassOf(Any::class))
    println(Root::class.isSuperclassOf(Leaf::class))
    println(Leaf::class.isSuperclassOf(Root::class))
    println(Any::class.isSuperclassOf(Other::class))

    println(Other::class.createType())
    println(Other::class.starProjectedType)
    println(Other::class.createType(nullable = true))
    try {
        Other::class.createType(listOf(KTypeProjection.STAR))
    } catch (e: IllegalArgumentException) {
        println("IAE createType")
    }
}
