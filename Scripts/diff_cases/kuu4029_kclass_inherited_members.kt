// KUU-4029: `memberProperties`/`memberFunctions`/`members` include inherited
// members; `declaredMember*` stays self-only. Overrides surface once under
// the most-derived signature, and Any's equals/hashCode/toString arrive via
// the root superclass.
import kotlin.reflect.full.*

open class Grand(val g0: Int) {
    fun gf() = 0
}

open class Base(val b1: Int) : Grand(g0 = 0) {
    val b2 = "b"
    open fun bf() = 1
}

interface Iface {
    fun iface(): Int
    val ip: String
}

class Sub(val s1: Int, var s2: String) : Base(s1), Iface {
    fun sf() = 1
    val extra = "e"
    override fun bf() = 2
    override fun iface() = 3
    override val ip = "p"
    override fun toString() = "Sub"
}

fun main() {
    println("MP: " + Sub::class.memberProperties.map { it.name }.sorted())
    println("DMP: " + Sub::class.declaredMemberProperties.map { it.name }.sorted())
    println("MF: " + Sub::class.memberFunctions.map { it.name }.sorted())
    println("DMF: " + Sub::class.declaredMemberFunctions.map { it.name }.sorted())
    println("M: " + Sub::class.members.map { it.name }.sorted())
    println("Base MP: " + Base::class.memberProperties.map { it.name }.sorted())
    println("Base MF: " + Base::class.memberFunctions.map { it.name }.sorted())
}
