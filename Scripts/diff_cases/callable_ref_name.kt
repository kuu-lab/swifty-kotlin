import kotlin.reflect.KCallable
import kotlin.reflect.KFunction

fun topFun() = 3
val topVal = 4

class Box(val value: Int) {
    fun add(x: Int) = value + x
}

fun Int.double() = this * 2
fun <T> identity(value: T): T = value
fun makeRef() = ::topFun
fun callableName(value: KCallable<*>) = value.name

fun main() {
    val fr = ::topFun
    println(fr())
    println(fr.name)
    println((::topFun).name)
    val alias = fr
    println(alias.name)
    println(identity(fr).name)
    println(identity(fr)())
    println(makeRef().name)
    println(listOf(fr)[0].name)
    println(callableName(fr))
    val typed: KFunction<Int> = fr
    println(typed.name)

    val box = Box(10)
    val bound = box::add
    val unbound = Box::add
    println(bound.name)
    println(bound(2))
    println(identity(bound).name)
    println(identity(bound)(3))
    println(unbound.name)
    println(unbound(box, 5))
    val extension = Int::double
    println(extension.name)
    println(extension(6))

    val nullable = if (box.value == 10) ::topFun else null
    val absent = if (box.value == 0) ::topFun else null
    println(nullable?.name)
    println(absent?.name)

    val vr = ::topVal
    println(vr.get())
    println(vr.name)
    println(Box::value.name)
}
