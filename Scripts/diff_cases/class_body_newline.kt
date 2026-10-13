// KUU-2027: A newline before the body must keep members inside the class.
class Target(val value: Int)
{
    fun read(): Int = value
}
fun main() { println(Target(7).read()) }
