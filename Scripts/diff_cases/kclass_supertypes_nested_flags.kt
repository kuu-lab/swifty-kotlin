// KUU-1357: KClass supertypes (class + interface + builtin), nestedClasses,
// visibility, typed members, and KFunction modifier flags.
import kotlin.reflect.*

open class P
interface I1
interface I2
class C : P(), I1, I2
interface SubI : I1
class WithComp { companion object { val v = 1 } }
class Outer { class Nested { class Deep } inner class Inn }
class Mut { var m = 5; fun f() = 1 }
class Flags {
    inline fun il() = 1
    operator fun plus(i: Int) = 2
    infix fun ix(i: Int) = 3
}
fun main() {
    println(C::class.supertypes.size)
    println(SubI::class.supertypes.size)
    println(Int::class.supertypes.size)
    println(List::class.supertypes.size)
    println(C::class.supertypes)
    println(Int::class.supertypes)
    println(SubI::class.supertypes)
    println(Outer::class.nestedClasses.map { it.simpleName })
    println(WithComp::class.nestedClasses.map { it.simpleName })
    println(C::class.visibility)
    println(Mut::class.members.any { it.name == "m" })
    println(Flags::il.isInline)
    println(Flags::plus.isOperator)
    println(Flags::ix.isInfix)
    println(Flags::il.isSuspend)
}
