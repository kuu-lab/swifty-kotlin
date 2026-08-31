interface Greeter {
    val greeting: String
        get() = "Hello"
    fun greet(name: String): String = "$greeting, $name!"
}

class CustomGreeter : Greeter {
    override val greeting: String = "Hi"
}

class DefaultGreeter : Greeter

interface BaseInterface {
    val baseProp: String
        get() = "baseDefault"
    val overriddenInChild: String
        get() = "baseOverridden"
}

interface ChildInterface : BaseInterface {
    val childProp: String
        get() = "childDefault"
    override val overriddenInChild: String
        get() = "childOverridden"
}

open class BaseClass : ChildInterface {
    override val baseProp: String
        get() = "classBaseProp"
}

class ConcreteClass : BaseClass()

fun readBase(b: BaseInterface) {
    println("baseProp: ${b.baseProp}")
    println("overriddenInChild: ${b.overriddenInChild}")
}

fun readChild(c: ChildInterface) {
    println("childProp: ${c.childProp}")
}

fun main() {
    val g1 = CustomGreeter()
    val g2 = DefaultGreeter()
    println(g1.greet("Alice"))
    println(g2.greet("Bob"))
    println(g1.greeting)
    println(g2.greeting)

    val obj = ConcreteClass()
    readBase(obj)
    readChild(obj)
}
