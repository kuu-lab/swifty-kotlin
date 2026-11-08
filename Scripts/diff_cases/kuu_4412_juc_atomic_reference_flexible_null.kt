import java.util.concurrent.atomic.AtomicReference

// KUU-4412: java.util.concurrent.atomic.AtomicReference is a Java class, so
// its type variable is flexible — null is accepted for any type argument.
fun main() {
    val ref = AtomicReference<Any>(null)
    println(ref.get())                        // null
    ref.set(null)
    println(ref.get())                        // null
    ref.set("hello")
    println(ref.get())                        // hello
    println(ref.compareAndSet("hello", null)) // true
    println(ref.get())                        // null
    val s = AtomicReference<String>("a")
    println(s.get())                          // a
    s.set(null)
    println(s.get())                          // null
    val n = AtomicReference<Any?>(null)
    println(n.get())                          // null
    println(n.getAndSet("v"))                 // null
    println(n.get())                          // v
}
