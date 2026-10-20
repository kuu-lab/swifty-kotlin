// KUU-2022: Java peekLast preserves platform returns and nullable elements.
import java.util.LinkedList
fun <T> tail(q: LinkedList<T>): T = q.peekLast()
fun main() { val q = LinkedList<Int>(); q.add(7); println(tail(q))
    println("int:${q.peekLast() + 1}:${q.size}")
    println("unary:${-q.peekLast()}")
    val booleans = LinkedList<Boolean>()
    booleans.add(false)
    println("bool:${!booleans.peekLast()}:${booleans.peekLast() && true}:${false || booleans.peekLast()}")
    if (booleans.peekLast()) println("unexpected-condition") else println("condition:false")
    when { booleans.peekLast() -> println("unexpected-when"); else -> println("when:false") }
    val longs = LinkedList<Long>()
    longs.add(2147483648L)
    println("long:${longs.peekLast() + 1L}")
    val doubles = LinkedList<Double>()
    doubles.add(1.5)
    println("double:${doubles.peekLast() + 0.5}")
    val strings = LinkedList<String>()
    println("empty:${strings.peekLast()}:${strings.size}")
    println(strings.peekLast())
    print(strings.peekLast()); println()
    println("concat:" + LinkedList<Int>().peekLast())
    println(listOf<Int?>(1) + LinkedList<Int>().peekLast())
    strings.add("hello")
    val value: String = strings.peekLast()
    println("string:${value.length}:${tail(strings)}:${strings.size}")
    strings.clear()
    val empty: String? = tail(strings)
    println("clear:$empty:${strings.size}")
    val nullable = LinkedList<Int?>()
    println("nullable-empty:${tail(nullable)}")
    nullable.add(9)
    val number: Int? = tail(nullable)
    println("nullable-value:$number:${nullable.size}")
    nullable.add(null)
    println("nullable-null:${tail(nullable)}:${nullable.peekLast()}:${nullable.size}")
    checkPlatformNulls()
    val nullableStrings = LinkedList<String?>()
    nullableStrings.add(null)
    println("nullable-string:${tail(nullableStrings)}:${nullableStrings.size}")
}

fun concrete(q: LinkedList<String>): String = q.peekLast()
fun <T : Any> bounded(q: LinkedList<T>): T = q.peekLast()
fun consume(value: String) { println("unexpected-consume") }
fun checkPlatformNulls() {
    val empty = LinkedList<String>()
    try { val value: String = empty.peekLast(); println("unexpected-local") }
    catch (e: NullPointerException) { println("npe:local") }
    try { concrete(empty); println("unexpected-return") }
    catch (e: NullPointerException) { println("npe:return") }
    try { bounded(empty); println("unexpected-bound") }
    catch (e: NullPointerException) { println("npe:bound") }
    try { consume(empty.peekLast()); println("unexpected-argument") }
    catch (e: NullPointerException) { println("npe:argument") }
    val function: (String) -> Unit = { println("unexpected-function") }
    try { function(empty.peekLast()) }
    catch (e: NullPointerException) { println("npe:function") }
    val emptyInts = LinkedList<Int>()
    try { println(-emptyInts.peekLast()) }
    catch (e: NullPointerException) { println("npe:unary") }
    val emptyBooleans = LinkedList<Boolean>()
    try { println(emptyBooleans.peekLast() && true) }
    catch (e: NullPointerException) { println("npe:boolean") }
    try { println(!emptyBooleans.peekLast()) }
    catch (e: NullPointerException) { println("npe:boolean-not") }
    try { if (emptyBooleans.peekLast()) println("unexpected-condition") }
    catch (e: NullPointerException) { println("npe:condition") }
    try { when { emptyBooleans.peekLast() -> println("unexpected-when"); else -> println("unexpected-else") } }
    catch (e: NullPointerException) { println("npe:when") }
    println("short-circuit:${false && emptyBooleans.peekLast()}:${true || emptyBooleans.peekLast()}")
}
