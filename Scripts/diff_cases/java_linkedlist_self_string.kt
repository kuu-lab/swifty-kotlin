import java.util.LinkedList

private class EqualToAnything {
    override fun equals(other: Any?): Boolean = true
    override fun hashCode(): Int = 0
    override fun toString(): String = "other"
}

fun main() {
    val list = LinkedList<Any?>()
    println(list)
    list.add(null)
    list.add("tail")
    list.add(list)
    println(list)
    println(list.toString())
    val erased: Any = list
    println(erased)
    val child = LinkedList<Any?>()
    child.add("value")
    val parent = LinkedList<Any?>()
    parent.add(child)
    parent.add(EqualToAnything())
    parent.add(parent)
    println(parent)
}
