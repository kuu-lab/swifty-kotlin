class Box(val number: Int)
open class Parent(val number: Int)
class Child(): Parent(try { val zero = 0; 10 / zero } catch(e: ArithmeticException) { 11 })
fun shadow(): Int {
    val x = 1
    try { val x = 2; return x } finally { println(x) }
}
fun replace(): Int { try { return 7 } finally { return 8 } }
fun replaceException(flag: Boolean): Int {
    try {
        try { return 1 }
        finally { println("inner"); if (flag) throw IllegalStateException("replacement"); return 2 }
    } finally { println("outer") }
}
fun lexicalBreak(): Int {
    var n = 0
    while (n < 2) {
        try { while (n < 2) { n++; return 7 } }
        finally { break }
    }
    return 9
}
fun main() {
    println(shadow())
    println(replace())
    println(replaceException(false))
    try { println(replaceException(true)) } catch(e: IllegalStateException) { println(e.message) }
    println(lexicalBreak())
    val box = Box(try { throw IllegalArgumentException("arg"); 0 } catch(e: IllegalArgumentException) { 42 })
    println(box.number)
    println(Child().number)
    try {
        try { throw IllegalArgumentException("first") }
        catch(e: IllegalArgumentException) { throw IllegalStateException("catch") }
        finally { println("catch-finally") }
    } catch(e: IllegalStateException) { println(e.message) }
    val erased: Any = 42
    println(erased is Int)
    println(erased as? String)
    try { println(erased as String) } catch(e: ClassCastException) { println("cast") }
}
