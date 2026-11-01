// KUU-4065: `memberProperties`/`memberFunctions`/`members` on `object` and
// `interface` KClass values returned empty — member reflection registration
// was emitted only for `class` declarations. Objects/interfaces get the same
// member rows at module init (they declare no `<init>` symbols, so only the
// member half of the reflection initializer applies), and interfaces get a
// `-> kotlin.Any` typeParents edge so the inherited-member BFS reaches Any's
// `equals`/`hashCode`/`toString` like kotlin-reflect reports.
import kotlin.reflect.full.*

object O {
    var y: String = ""
    fun g(): Int = 1
}

interface IBase {
    val baseProp: Long
    fun baseFun()
}

interface I : IBase {
    var x: Int
    fun f()
    fun h(): String = "h"
}

class Outer {
    object NestedObj { val p: Int = 1 }
    interface NestedIface { val q: Int }
    companion object { val c: String = "c" }
}

fun main() {
    println("O MP: " + O::class.memberProperties.map { it.name }.sorted())
    println("O MF: " + O::class.memberFunctions.map { it.name }.sorted())
    println("O M: " + O::class.members.map { it.name }.sorted())
    println("I MP: " + I::class.memberProperties.map { it.name }.sorted())
    println("I DMP: " + I::class.declaredMemberProperties.map { it.name }.sorted())
    println("I MF: " + I::class.memberFunctions.map { it.name }.sorted())
    println("I M: " + I::class.members.map { it.name }.sorted())
    println("NObj MP: " + Outer.NestedObj::class.memberProperties.map { it.name }.sorted())
    println("NIface M: " + Outer.NestedIface::class.members.map { it.name }.sorted())
    println("Comp MP: " + Outer.Companion::class.memberProperties.map { it.name }.sorted())
    println("O ctor: " + O::class.constructors.size)
    println("I ctor: " + I::class.constructors.size)
}
