// KUU-1391: `::prop.isInitialized` must link and read the backing storage
// directly. kotlinc only permits it where the backing field is reachable:
// members inside the declaring scope, top-level properties in the same file.
class C {
    lateinit var name: String
    fun self() = this::name.isInitialized
    fun other(c: C) = c::name.isInitialized
    fun bare() = ::name.isInitialized
}

lateinit var top: String

class R {
    fun readTop() = ::top.isInitialized
}

object O {
    lateinit var label: String
    fun self() = this::label.isInitialized
    fun bare() = ::label.isInitialized
}

class Host {
    companion object {
        lateinit var tag: String
        fun self() = this::tag.isInitialized
        fun bare() = ::tag.isInitialized
    }
}

fun main() {
    val c = C()
    println(::top.isInitialized)
    println(R().readTop())
    println(c.self())
    println(c.other(C()))
    println(c.bare())
    println(O.self())
    println(O.bare())
    println(Host.Companion.self())
    println(Host.Companion.bare())
    c.name = "n"
    top = "t"
    O.label = "l"
    Host.Companion.tag = "g"
    println(::top.isInitialized)
    println(R().readTop())
    println(c.self())
    println(c.other(c))
    println(c.bare())
    println(O.self())
    println(O.bare())
    println(Host.Companion.self())
    println(Host.Companion.bare())
}
