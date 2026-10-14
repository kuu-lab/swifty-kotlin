open class Base(val s: String)
typealias B = Base

open class Box<T>(val v: T)
typealias StringBox = Box<String>
typealias StringBox2 = StringBox
typealias AnyBox<T> = Box<T>

class FromPlain : B("plain")
class FromFixed : StringBox("fixed")
class FromChain : StringBox2("chain")
class FromGeneric : AnyBox<String>("generic")

fun main() {
    println(FromPlain().s)
    println(FromFixed().v.length)
    println(FromChain().v.uppercase())
    println(FromGeneric().v)
}
