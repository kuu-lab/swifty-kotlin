// KUU-2027: Same-line, explicit, no-constructor, and supertype body controls.
open class Base
interface First
interface Second
class SameLine(val value: Int) { fun read(): Int = value }
class Explicit constructor(val value: Int)
{
    fun read(): Int = value
}
class NoConstructor
{
    fun read(): Int = 7
}
class Inherited(val value: Int) : Base()
{
    fun read(): Int = value
}
class Multiple(val value: Int)
    : First, Second
{
    fun read(): Int = value
}
class Following
fun after(): Int = 7
fun main() {
    println(SameLine(7).read())
    println(Explicit(7).read())
    println(NoConstructor().read())
    println(Inherited(7).read())
    println(Multiple(7).read())
    println(after())
}
