// KUU-2366: a data class must inherit a final superclass toString(), while open or
// absent implementations still allow the generated data-class representation.
abstract class FinalBase {
    final override fun toString(): String = "base"
}
abstract class FinalMiddle : FinalBase()
data class FinalChild(val field: String) : FinalMiddle()

open class OpenBase {
    override fun toString(): String = "base"
}
data class OpenChild(val field: String) : OpenBase()

abstract class PlainBase
data class PlainChild(val field: String) : PlainBase()

data class ExplicitChild(val field: String) : OpenBase() {
    override fun toString(): String = "own"
}

fun main() {
    println(FinalChild("x").toString())
    println(OpenChild("x").toString())
    println(PlainChild("x").toString())
    println(ExplicitChild("x").toString())
}
