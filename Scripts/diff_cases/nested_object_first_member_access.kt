open class Base(val flag: Boolean, val num: Int)
class Holder {
    object O : Base(true, 42)
    fun check() { println("inner flag=${O.flag} num=${O.num}") }
}
class Holder2 {
    object O2 : Base(true, 43) { val own = "mine" }
    fun check2() { println("${O2.flag} ${O2.num} ${O2.own}") }
}
object Outer {
    object O3 : Base(true, 44)
    fun check3() { println("${O3.flag} ${O3.num}") }
}
fun main() {
    Holder().check()
    Holder2().check2()
    Outer.check3()
}
