open class Parent<T>(var inherited: String) {
    fun greet(): String = "p-$inherited"
}
class Child {
    companion object : Parent<Child>("OK") {
        val own: String = "C"
    }
    fun readInherited(): String = inherited
    fun readInheritedFun(): String = greet()
    fun readOwn(): String = own
    fun bump(): String { inherited = inherited + "!"; return inherited }
    fun readQualified(): String = Companion.inherited + ":" + Child.inherited
}
class Outer {
    companion object : Parent<Outer>("OUTER")
    class Nested {
        fun read(): String = inherited
    }
}
open class Base {
    companion object : Parent<Base>("SUPER")
}
class Sub : Base() {
    fun read(): String = inherited
}
fun main() {
    val c = Child()
    println(c.readInherited())
    println(c.readInheritedFun())
    println(c.readOwn())
    println(c.bump())
    println(c.readQualified())
    println(Outer.Nested().read())
    println(Sub().read())
}
