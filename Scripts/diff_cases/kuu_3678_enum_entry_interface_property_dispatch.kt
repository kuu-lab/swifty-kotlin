interface HasValue { val value: String }
interface MutableValue { var value: String }
enum class Inferred : HasValue {
    A { override val value = "inferred" }
}
enum class Explicit : HasValue {
    A { override val value: String = "explicit" }
}
enum class Custom : HasValue {
    A { override val value: String get() = "custom" }
}
enum class Mutable : MutableValue {
    A { override var value = "before" }
}

fun main() {
    println(Inferred.A.value)
    println(Explicit.A.value)
    println(Custom.A.value)
    val widened: HasValue = Inferred.A
    println(widened.value)
    val mutable = Mutable.A
    mutable.value = "after"
    println(mutable.value)
    val mutableInterface: MutableValue = Mutable.A
    mutableInterface.value = "interface"
    println(mutableInterface.value)
}
