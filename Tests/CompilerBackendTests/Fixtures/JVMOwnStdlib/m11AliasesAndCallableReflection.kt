typealias Count = Int
typealias Numbers<T> = List<T>
var top: Count = 2
class Box(var value: Count) { fun add(n: Count): Count = value + n }
fun twice(n: Count): Count = n * 2
fun main() {
    println(Box::class.simpleName); println(Box::class.qualifiedName)
    val b = Box(20); println(b::class.isInstance(b))
    val f = ::twice; println(f.name); println(f(21)); println(f.call(3))
    val bound = b::add; println(bound(4)); println(bound.parameters.size)
    val p = Box::value; println(p.name); println(p.get(b)); p.set(b, 30)
    val bp = b::value; println(bp.get()); bp.set(40); println(b.value)
    val t = ::top; println(t.get()); t.set(5); println(top)
    val ctor = ::Box; println(ctor(7).value)
    val numbers: Numbers<Count> = listOf(1, 2); println(numbers.size)
    println(Int::class.simpleName); println(Box::class.java.name)
}
