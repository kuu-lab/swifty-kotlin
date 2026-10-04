// BUG-inner-outer: `this@Label` qualifying an ancestor class reached through
// two or more `inner class` `$outer` hops, referenced from inside an object
// literal's own member function (not the enclosing function itself).
class Outer(val tag: String) {
    inner class Middle(val mtag: String) {
        fun make(): String {
            val obj = object {
                fun show(): String {
                    return this@Outer.tag + "/" + this@Middle.mtag
                }
            }
            return obj.show()
        }
    }
}

fun main() {
    val o = Outer("hello")
    val m = o.Middle("world")
    println(m.make())
}
