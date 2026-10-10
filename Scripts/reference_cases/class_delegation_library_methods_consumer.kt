import delegation.methods.*

class MutableLabel : Label {
    var current: String = "consumer"
    override fun label(): String = current
    override fun value(offset: Int): Int = 40 + offset
    override fun fail(): Int = throw IllegalStateException("consumer failure")
}

class ChildLabel(original: Label) : WrappedLabel(original)

fun main() {
    val original = MutableLabel()
    val wrapped = WrappedLabel(original)
    val dynamic: Label = wrapped
    val child = ChildLabel(original)
    println(dynamic.label())
    println(wrapped.label())
    println(child.label())
    println(dynamic.value(2))
    println(wrapped.value(offset = 3))
    println(child.value(offset = 4))
    original.current = "changed"
    println(dynamic.label())
    println(child.label())
    println(WrappedLabel(KnownLabel()).label())
    try {
        dynamic.fail()
        error("missing failure")
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
