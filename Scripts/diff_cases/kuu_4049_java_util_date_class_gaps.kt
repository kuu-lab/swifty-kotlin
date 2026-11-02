import java.util.Date
import java.util.Vector
import java.util.Stack
import java.util.Hashtable
import java.util.Enumeration
import java.lang.InterruptedException

fun main() {
    // java.util.Date: Comparable + after/before/time
    val d0 = Date(0)
    val d1 = Date(1000)
    println(d1.after(d0))
    println(d0.after(d0))
    println(d0.before(d1))
    println(d0.before(d0))
    println(d0.compareTo(d1))
    println(d1.compareTo(d0))
    println(d0.compareTo(d0))
    println(d0.time)
    println(d1.time)
    println(d1 < d0)
    println(d1 > d0)
    println(Date(0) == Date(0))
    println(d0 == d1)
    println(Date(5).hashCode())

    // java.util.Vector.elements() + Enumeration.toList()
    val v = Vector<String>()
    v.add("a")
    v.add("b")
    val en: Enumeration<String> = v.elements()
    println(en.toList())
    println(Vector<String>().elements().toList())
    println(Hashtable<String, Int>().also { it["k"] = 1 }.elements().toList())

    // java.util.Stack.search(): 1-based distance from top, -1 when absent
    val s = Stack<String>()
    s.push("x")
    s.push("y")
    s.push("z")
    println(s.search("z"))
    println(s.search("y"))
    println(s.search("x"))
    println(s.search("missing"))
    println(s.search(5))
    println(Stack<String>().search("a"))

    // java.lang.InterruptedException: qualified + imported spellings
    println(java.lang.InterruptedException("qualified").message)
    println(InterruptedException("imported").message)
    println(InterruptedException().message)

    // java.lang.Class: methods / isInterface / canonicalName
    val k = String::class.java
    println(k.methods.size >= 0)
    println(k.isInterface)
    println(Runnable::class.java.isInterface)
    println(Int::class.java.isInterface)
    println(IntArray::class.java.isInterface)
    println(k.canonicalName)
}
