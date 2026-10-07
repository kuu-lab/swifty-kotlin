// An unbound reference to an open/abstract class property must dispatch the
// getter through the vtable, not call the base accessor statically.
abstract class Shape { abstract val sides: Int }
open class Base { open val tag: String get() = "base" }
class Tri : Shape() { override val sides = 3 }
class Sq : Shape() { override val sides = 4 }
class Derived : Base() { override val tag: String get() = "derived" }

fun main() {
    println(listOf(Tri(), Sq()).map(Shape::sides))
    println(listOf(Base(), Derived()).map(Base::tag))
    val ref = Base::tag
    println(ref.get(Derived()))
}
