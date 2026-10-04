interface Shape { fun area(): Int }
interface Named { val label: String }
abstract class Base : Shape { override fun toString() = "Base:" + area() }
class Sq(val s: Int) : Base(), Named { override fun area() = s * s; override val label = "sq" }
class Ci(val r: Int) : Base(), Named { override fun area() = 3 * r * r; override val label = "ci" }
class Tri(val h: Int) : Shape { override fun area() = h }
sealed class Json { class Num(val v: Double) : Json(); class Str(val s: String) : Json() }
interface Box<T> { fun get(): T }
class IntBox(val v: Int) : Box<Int> { override fun get() = v }
class OtherIntBox(val v: Int) : Box<Int> { override fun get() = v + 1 }
class StrBox(val v: String) : Box<String> { override fun get() = v }

fun main() {
    val bases = listOf(Sq(2), Ci(1))
    println(bases.map { it.area() })
    println(bases.map { it.toString() })
    val shapes = listOf(Sq(2), Tri(5))
    println(shapes.map { it.area() })
    val n: Shape? = if (shapes.size > 5) null else Sq(3)
    println(n?.area())
    val boxes = listOf(IntBox(1), OtherIntBox(1))
    println(boxes.map { it.get() })
    val js = listOf(Json.Num(1.0), Json.Str("x"))
    println(js.size)
    val pick = when (shapes.size) { 1 -> Sq(1); 2 -> Tri(7); else -> Ci(2) }
    println(pick.area())
    val ms = mapOf("a" to Sq(1), "b" to Tri(4))
    println(ms.values.map { it.area() })
    val o: List<Any> = listOf(IntBox(1), StrBox("s"))
    println(o.size)
}
