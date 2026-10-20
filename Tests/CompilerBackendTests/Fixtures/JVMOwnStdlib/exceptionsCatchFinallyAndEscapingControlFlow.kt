class Failure(message: String): RuntimeException(message)
fun returning(): Int {
    try { return 7 } finally { println("return-finally") }
}
fun nested(): Int {
    try {
        try { throw IllegalArgumentException("inner") }
        finally { println("inner-finally") }
    } catch (e: RuntimeException) { println(e.message); return 9 }
    finally { println("outer-finally") }
}
fun main() {
    val result = try { throw Failure("failure"); 0 }
        catch (e: IllegalArgumentException) { 1 }
        catch (e: Failure) { println(e.message); 42 }
        finally { println("finally") }
    println(result)
    println(returning())
    println(nested())
    for (i in 1..3) {
        try { if (i == 1) continue; if (i == 2) break }
        finally { println(i) }
    }
    try { println(intArrayOf(1)[5]) }
    catch (e: IndexOutOfBoundsException) { println("bounds") }
    try { val n = 0; println(10 / n) }
    catch (e: ArithmeticException) { println("divide") }
}
