// KUU-3110: synthesized data class toString must dispatch virtually on
// class-typed properties so the property's runtime override is used.
open class Base {
    override fun toString(): String = "base"
}
class Child : Base() {
    override fun toString(): String = "child"
}
interface Named {
    override fun toString(): String
}
class Impl : Named {
    override fun toString(): String = "impl"
}
data class Holder(val value: Base)
data class Nullable(val value: Base?)
data class SelfRef(val inner: Holder)
data class HI(val v: Named)
data class HP(val p: Pair<Base, Int>)
fun main() {
    println(Holder(Child()))
    println(Holder(Base()))
    println(Nullable(Child()))
    println(Nullable(null))
    println(SelfRef(Holder(Child())))
    println(HI(Impl()))
    println(HP(Pair(Child(), 3)))
}
