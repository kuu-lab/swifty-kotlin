interface I
operator fun I.invoke(): String = "OK"
class C : I
object H { val value = C() }
fun box(): String = H?.value()!!
fun main() { print(box()) }
