// EXPECT-REJECT
// KUU-3254: a data class's generated componentN() must be able to override
// each effective inherited member with the same name and arity. kotlinc
// reports "generated for the data class conflicts with the supertype
// member" when the inherited member is effectively final, or when its
// return type is incompatible with the generated one — for superclass and
// interface members alike. Each error lands on the data class line.
open class FinalBase {
    fun component1(): String = "x"
}
data class FinalMember(val field: String) : FinalBase()

open class MismatchBase {
    open fun component1(): Int = 1
}
data class ReturnMismatch(val field: String) : MismatchBase()

interface InterfaceMismatch {
    fun component1(): Int
}
data class InterfaceConflict(val field: String) : InterfaceMismatch

fun main() {
    println(FinalMember("x"))
    println(ReturnMismatch("x"))
    println(InterfaceConflict("x"))
}
