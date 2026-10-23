// KUU-2955: an inner-class member constructing a fresh instance of its
// enclosing local class must pass the captured outer locals through the
// `$outer` chain. Based on JetBrains localClasses/closureOfInnerLocalClass.
fun box(): String {
    var log = ""
    var s: Any? = null
    for (t in arrayOf("1", "2", "3")) {
        class C() {
            val y = t
            inner class D() {
                fun copyOuter() = C()
            }
        }
        if (s == null) { s = C() }
        val c = (s as C).D().copyOuter()
        log += c.y
    }
    if (log != "111") return "fail: ${log}"
    return "OK"
}

fun main() {
    for (t in arrayOf("1", "2", "3")) {
        class C() {
            val y = t
            inner class D() {
                fun copyOuter() = C()
            }
        }
        val c = C().D().copyOuter()
        println(c.y)
    }
    println(box())
}
