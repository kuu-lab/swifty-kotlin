// KUU-3243: an unqualified `super.<member>` resolves when exactly one direct
// supertype actually provides the member through real supertype edges —
// `Any` members reachable from every interface do not make the call
// ambiguous (kotlinc diamond rule).
interface Left
interface Right

class AnyChild : Left, Right {
    override fun toString() = "child:" + super.toString().length.toString()
    fun describe() = super.toString().isEmpty().toString()
}

open class Base {
    fun classOnly() = "base"
    override fun toString() = "B"
}
interface Iface {
    fun interfaceOnly() = "iface"
}

class Multi : Base(), Iface {
    fun pick() = super.classOnly() + "|" + super.interfaceOnly() + "|" + super.toString()
}

fun main() {
    val c = AnyChild()
    println(c.toString().startsWith("child:"))
    println(c.describe())
    println(Multi().pick())
}
