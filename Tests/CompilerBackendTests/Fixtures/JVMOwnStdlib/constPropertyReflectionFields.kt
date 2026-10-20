import kotlin.reflect.KProperty1

const val top = "top"
object Constants { const val FLAG = true }
class Limits {
    companion object Named {
        const val MIN = -9223372036854775807L - 1L
        val ordinary = 7
    }
}
class Cold {
    companion object {
        init { println("unexpected initialization") }
        const val NUMBER = 42
    }
}
fun source(): Limits.Named { print("R"); return Limits.Named }
fun main() {
    println(Cold.NUMBER)
    println(Limits.MIN)
    println(source().MIN)
    println(Limits.ordinary)
    val bound = Limits::MIN
    println(bound.get()); println(bound.call()); println(bound.callBy(emptyMap()))
    println(bound.parameters.size); println(bound.isConst)
    val member = Limits.Named::class.members.first { it.name == "MIN" }
    println(member.parameters.size)
    println(member.call(Limits.Named))
    println(member.callBy(mapOf(member.parameters[0] to Limits.Named)))
    println((member as KProperty1<Limits.Named, Long>).get(Limits.Named))
    val topReference = ::top
    println(topReference.get()); println(topReference.callBy(emptyMap()))
    println(topReference.parameters.size); println(topReference.isConst)
    val objectReference = Constants::FLAG
    println(objectReference.get()); println(objectReference.call())
}
