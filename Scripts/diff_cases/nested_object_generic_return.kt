// KUU-1966: a nested singleton's String override must satisfy the erased T-return ABI.
abstract class GT<T : Any> {
    abstract fun conv(s: String): T
    abstract fun name(): String
    abstract fun num(): Int
}
class Holder { object S : GT<String>() {
    override fun conv(s: String) = s
    override fun name() = "objname"
    override fun num() = 7
} }
fun main() {
    val b: GT<String> = Holder.S
    println("conv=${b.conv("hi")}")
    println("name=${b.name()}")
    println("num=${b.num()}")
}
