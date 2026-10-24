// KUU-3230: a data class must keep final superclass implementations of
// toString/hashCode/equals instead of regenerating them, including when the
// implementation is inherited through a deeper chain. The direct `x.toString()`
// call on such a class is a vtable call rooted at the synthetic `Any.toString`
// declaration and must use the flat String aggregate ABI, not the raw-handle
// runtime helper signature.
abstract class FinalMembersBase {
    final override fun toString(): String = "OK"
    final override fun hashCode(): Int = 42
    final override fun equals(other: Any?): Boolean = false
}
data class FinalMembersChild(val field: String) : FinalMembersBase()

abstract class RootBase {
    final override fun toString(): String = "ROOT"
}
abstract class MiddleBase : RootBase()
data class DeepChild(val field: String) : MiddleBase()

// A non-data class takes the same virtual-call path for inherited toString.
class PlainChild : FinalMembersBase()

fun main() {
    val d = FinalMembersChild("x")
    println(d.toString())
    println(d.hashCode())
    println(d.equals(d))
    println(DeepChild("x").toString())
    println(PlainChild().toString())
}
