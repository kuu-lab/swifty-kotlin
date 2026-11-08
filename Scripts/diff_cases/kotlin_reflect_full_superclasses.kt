import kotlin.reflect.full.*

class CC(val p: String) { companion object { const val K = 5 } }
open class A
interface I
class B : A(), I
object Obj

fun main() {
    println(CC::class.companionObjectInstance != null)
    println(CC::class.companionObjectInstance!!::class)
    println(Obj::class.companionObjectInstance)
    println(B::class.superclasses)
    println(B::class.superclasses.size)
    println(String::class.superclasses.size)
    println(Int::class.superclasses)
}
