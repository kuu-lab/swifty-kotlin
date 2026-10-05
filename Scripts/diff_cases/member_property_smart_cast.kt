data class Args(val x: String?, val value: Any?)
class Outer(val inner: Args)

fun main() {
    val args = Args("hello", "smart")
    val other = Args(null, null)
    if (args.x != null) println(args.x.length)
    if (args.x != null && args.x.length > 0) println(args.x.length)
    if (other.x == null) println("null") else println(other.x.length)
    when (args.x) {
        null -> println(0)
        else -> println(args.x.length)
    }
    if (args.value is String) println(args.value.length)
    val outer = Outer(args)
    if (outer.inner.x != null) println(outer.inner.x.length)
    require(args.x != null)
    println(args.x.length)
    requireNotNull(outer.inner.x)
    println(outer.inner.x.length)
    checkNotNull(args.x) { "missing" }
    println(args.x.length)
    when (args.value) {
        is String -> println(args.value.length)
        else -> println(0)
    }
}
