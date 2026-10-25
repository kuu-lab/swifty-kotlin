// EXPECT-REJECT
fun <in T> topIn(value: T): T = value
fun <out T> topOut(): T? = null
class Member { fun <in T> member(value: T): T = value }
interface GenericMember { fun <out T> member(): T? }
fun outer() {
    fun <out T> local(): T? = null
}
val <out T> T.identity: T get() = this
fun main() {}
