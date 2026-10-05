fun widen(f: Function1<Int, String>): (Int) -> String = f
fun assign(f: Function1<Int, String>): String {
    val g: (Int) -> String = f
    return g(10)
}
fun forward(f: Function1<Int, String>): String = widen(f)(12)
fun narrow(f: (Int) -> String): Function1<Int, String> = f
fun <T, R> generic(f: Function1<T, R>): (T) -> R = f
fun <T> ordinary(f: (T) -> String, value: T): String = f(value)
fun zero(f: Function0<Int>): () -> Int = f
fun two(f: Function2<Int, Int, Int>): (Int, Int) -> Int = f
fun three(f: Function3<Int, Int, Int, Int>): (Int, Int, Int) -> Int = f
fun four(f: Function4<Int, Int, Int, Int, Int>): (Int, Int, Int, Int) -> Int = f
fun five(f: Function5<Int, Int, Int, Int, Int, Int>): (Int, Int, Int, Int, Int) -> Int = f
fun nullable(f: Function1<Int, String>?): ((Int) -> String)? = f
fun nullableResult(f: Function1<Int, String?>): (Int) -> String? = f
fun makeNominal(): Function1<Int, String> = { "return:" + it }
fun makeReference(): Function1<Int, String> = ::text
fun text(x: Int): String = "ref:" + x

fun main() {
    val h: Function1<Int, String> = { x: Int -> x.toString() }
    println(widen(h)(9))
    println(assign(h))
    println(widen { x -> x.toString() }(11))
    println(forward(h))
    val g: (Int) -> String = h
    println(g(13))
    println(widen(narrow { x -> x.toString() })(14))
    val offset = 20
    val captured: Function1<Int, String> = { (it + offset).toString() }
    println(widen(captured)(2))
    println(widen { (it + offset).toString() }(3))
    val label = "cap:"
    println(widen { label + (it + offset) }(4))
    val ref: Function1<Int, String> = ::text
    println(widen(ref)(15))
    println(widen(::text)(16))
    println(widen(makeNominal())(21))
    println(widen(makeReference())(22))
    val toStringRef: Function1<Int, String> = Int::toString
    println(widen(toStringRef)(23))
    val sumRef: Function2<Int, Int, Int> = Int::plus
    println(two(sumRef)(24, 25))
    println(sumRef(26, 27))
    val f0: Function0<Int> = { 7 }
    val f3: Function3<Int, Int, Int, Int> = { a, b, c -> a + b + c }
    val f4: Function4<Int, Int, Int, Int, Int> = { a, b, c, d -> a + b + c + d }
    val f5: Function5<Int, Int, Int, Int, Int, Int> = { a, b, c, d, e -> a + b + c + d + e }
    println(f0())
    println(h(28))
    println(f3(1, 2, 3))
    println(f4.invoke(1, 2, 3, 4))
    println(f5(1, 2, 3, 4, 5))
    println(generic<Int, String>(h)(17))
    println(ordinary(h, 19))
    println(generic<Int, Int> { it + offset }(5))
    println(zero { offset }())
    println(two { a, b -> a * 10 + b }(1, 2))
    println(three { a, b, c -> a + b + c + offset }(1, 2, 3))
    println(four { a, b, c, d -> a + b + c + d }(1, 2, 3, 4))
    println(five { a, b, c, d, e -> a + b + c + d + e }(1, 2, 3, 4, 5))
    println(nullable(null) == null)
    println(nullable(h)?.invoke(18))
    println(nullableResult { if (it == 0) null else "ok" }(0))
    println(nullableResult { if (it == 0) null else "ok" }(1))
}
