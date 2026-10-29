// EXPECT-REJECT
// KUU-3766: an unqualified reference to a `private` member declared on a
// companion object's supertype resolves through implicit-receiver lookup, so
// it must report an inaccessible-member diagnostic (kotlinc: "cannot access
// ... it is private"), not an unresolved reference/function.
open class Base {
    private fun hidden(): Int = 1
    private val secret: Int = 2
}
class WithComp {
    companion object : Base()
    fun callHidden(): Int = hidden()
    fun readSecret(): Int = secret
}
fun main() { println(WithComp().callHidden()) }
