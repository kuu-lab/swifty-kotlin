interface Service { fun value(): String }
object Impl : Service { override fun value(): String = "delegate" }
fun makeService(): Service = Impl

class ValueDelegate {
    operator fun getValue(thisRef: Any?, property: Any?): String = "property delegate"
}

val actual by ValueDelegate()
val direct = object : Service by Impl {}
val chosen = object : Service by when (true) { else -> Impl } {}
val called = object : Service by makeService() {}
val ordinary = object : Service { override fun value(): String = "ordinary" }
class Holder { val member = object : Service by Impl {} }

fun main() {
    println(direct.value())
    println(chosen.value())
    println(called.value())
    println(Holder().member.value())
    println(actual)
    println(ordinary.value())
}
