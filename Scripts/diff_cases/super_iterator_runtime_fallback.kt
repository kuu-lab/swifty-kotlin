// KUU-2047: runtime interface bridges must not compete with concrete super implementations.
open class Base : Iterator<Int> {
    override fun hasNext(): Boolean = false
    override fun next(): Int = 7
}
class Child : Base(), MutableIterator<Int> {
    override fun next(): Int = super.next()
    override fun remove() {}
}
class Qualified : Base(), MutableIterator<Int> {
    override fun next(): Int = super<Base>.next()
    override fun remove() {}
}
interface I { fun next(): Int }
interface M : I { fun remove() }
open class B : I { override fun next(): Int = 9 }
class C : B(), M {
    override fun next(): Int = super.next()
    override fun remove() {}
}
open class ThrowingBase : Iterator<Int> {
    override fun hasNext(): Boolean = false
    override fun next(): Int = throw NoSuchElementException("empty")
}
class ThrowingChild : ThrowingBase(), MutableIterator<Int> {
    override fun next(): Int = super.next()
    override fun remove() {}
}
fun main() {
    println(Child().next())
    println(Qualified().next())
    println(C().next())
    println(Child().hasNext())
    try {
        ThrowingChild().next()
    } catch (e: NoSuchElementException) {
        println(e.message)
    }
}
