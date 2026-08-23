open class DirectRead {
    open val p: Int = 5
}

open class Base {
    open val p: Int = 5
}

class BaseChild : Base()

open class Parent {
    open val p: Int = 6
}

class Child : Parent() {
    override val p: Int = 7
}

fun main() {
    println(DirectRead().p)
    val base: Base = BaseChild()
    println(base.p)
    val parent: Parent = Child()
    println(parent.p)
}
