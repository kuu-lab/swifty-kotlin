// KUU-3571: projected Comparator SAM lambdas and function-type intersection bounds.
fun <T> foo(comparator: kotlin.Comparator<in T>, a: T, b: T) = comparator.compare(a, b)
fun bar(x: Int, y: Int) = foo<Int>({ a, b -> a - b }, x, y)

fun interface KRunnable { fun invoke() }
fun interface KBoolean { fun invoke(b: Boolean) }
fun useFunInterface(fn: KRunnable) { fn.invoke() }
fun useFunInterfacePredicate(fn: KBoolean) { fn.invoke(true) }

fun <T> testIntersection(x: T) where T : () -> Unit, T : (Boolean) -> Unit {
    useFunInterface(x)
    useFunInterfacePredicate(x)
}

var result = ""
object Test : () -> Unit, (Boolean) -> Unit {
    override fun invoke() { result += "O" }
    override fun invoke(p1: Boolean) { if (p1) result += "K" }
}

fun box(): String {
    val comparison = bar(42, 117)
    testIntersection(Test)
    return if (comparison < 0 && result == "OK") "OK" else "FAIL"
}

fun main() { println(box()) }
