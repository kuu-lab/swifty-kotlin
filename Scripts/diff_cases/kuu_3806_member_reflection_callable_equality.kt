// KUU-3806: a member obtained through KClass reflection must equal the
// matching unbound callable reference, like the JVM's kotlin-reflect.
import kotlin.reflect.full.*

class C {
    fun foo() {}
    fun quux(x: Int) {}
    suspend fun susp() {}
    operator fun plus(other: C): C = this
    val bar = 42
    var mutableProp = "m"
}

fun main() {
    val c = C()
    println(C::class.functions.find { it.name == "foo" } == C::foo)
    println(C::class.functions.find { it.name == "quux" } == C::quux)
    println(C::class.functions.find { it.name == "susp" } == C::susp)
    println(C::class.functions.find { it.name == "plus" } == C::plus)
    println(C::class.memberProperties.find { it.name == "bar" } == C::bar)
    println(C::class.memberProperties.find { it.name == "mutableProp" } == C::mutableProp)
    println(C::class.members.find { it.name == "foo" } == C::foo)
    println(C::class.members.find { it.name == "bar" } == C::bar)
    println(C::class.functions.find { it.name == "foo" } != c::foo)
    println(C::class.memberProperties.find { it.name == "bar" } != c::bar)
    println(c::foo == c::foo)
    println(c::bar == c::bar)
    println(C::foo != C::quux)
    println(C::foo == C::foo)
    println(c::foo != C()::foo)
    println(C::class.functions.find { it.name == "foo" }?.hashCode() == C::foo.hashCode())
    println(C::class.memberProperties.find { it.name == "bar" }?.hashCode() == C::bar.hashCode())
}
