interface Operation { operator fun invoke(n: Int = 21): Int }
class Implementation: Operation { override fun invoke(n: Int): Int = n * 2 }
class Forward(delegate: Operation): Operation by delegate
class Immediate: Lazy<Int> {
    override val value: Int get() = 42
    override fun isInitialized(): Boolean = true
}
class LazyForward(delegate: Lazy<Int>): Lazy<Int> by delegate
fun main() {
    val operation = Forward(Implementation())
    println(operation()); println(Forward(Implementation())(20))
    val direct: Lazy<Int> = Immediate()
    println(direct.value)
    val forwarded: Lazy<Int> = LazyForward(direct)
    println(forwarded.value); println(forwarded.isInitialized())
    val delegated: Int by Immediate(); println(delegated)
}
