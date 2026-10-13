// KUU-1429: function types are valid `as`/`as?` targets, including for
// labeled lambdas in call-argument position. All lambdas are invoked so the
// output stays deterministic (function-object toString is not portable).
fun apply(f: () -> Int): Int = f()

fun main() {
    println(apply(foo@{ 7 } as () -> Int))
    println((foo@{ 8 } as () -> Int)())
    println(apply({ 9 } as () -> Int))
    println((foo@{ 10 } as? () -> Int)?.invoke())

    val s: Any = "not a function"
    try {
        s as () -> Int
        println("no-cce")
    } catch (e: ClassCastException) {
        println("cce")
    }
    println(s as? () -> Int == null)

    println(apply(foo@{ return@foo 11 } as () -> Int))

    val p: (Int) -> Int = lbl@{ x: Int -> x + 1 } as (Int) -> Int
    println(p(41))
    val r0: Int.() -> Int = { this * 2 }
    val r = r0 as Int.() -> Int
    println(r(3))
}
