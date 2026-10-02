fun main() {
    open class LBase(val b: Int) { open fun d() = "LBase$b"; fun callD() = d() }
    class LDer : LBase(9) { override fun d() = "LDer(" + super.d() + ")" }
    val lb: LBase = LDer()
    println(lb.d())
    println(LDer().d())
    println(lb.callD())
    abstract class Shape { abstract fun area(): Int }
    class Sq(val s: Int) : Shape() { override fun area() = s * s }
    println(listOf<Shape>(Sq(2), Sq(3)).map { it.area() })
}
