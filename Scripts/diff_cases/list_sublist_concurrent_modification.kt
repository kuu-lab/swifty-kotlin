fun sizeOf(list: List<Int>): Int = list.size

fun checkInvalidView(operation: String) {
    val base = mutableListOf(1, 2, 3, 4)
    val sub = base.subList(1, 3)
    base.add(5)
    try {
        when (operation) {
            "size" -> println(sub.size)
            "size-call" -> println(sizeOf(sub))
            "get" -> println(sub[0])
            "set" -> sub[0] = 99
            "add" -> sub.add(99)
            "add-at" -> sub.add(0, 99)
            "remove" -> sub.remove(2)
            "removeAt" -> sub.removeAt(0)
            "clear" -> sub.clear()
            "iterator" -> sub.iterator()
            "listIterator" -> sub.listIterator()
            "listIterator-at" -> sub.listIterator(0)
            "subList" -> println(sub.subList(0, 1).size)
            "isEmpty" -> println(sub.isEmpty())
            "contains" -> println(sub.contains(2))
            "for" -> for (value in sub) println(value)
        }
        println("missed: " + operation)
    } catch (e: ConcurrentModificationException) {
        println("CME: " + operation)
    }
    println(base)
}

fun main() {
    val base = mutableListOf(1, 2, 3, 4)
    val sub = base.subList(1, 3)
    sub[0] = 99
    println(base)
    base.add(5)
    try {
        println(sub.size)
    } catch (e: ConcurrentModificationException) {
        println("CME: reproduction")
    }

    checkInvalidView("size")
    checkInvalidView("size-call")
    checkInvalidView("get")
    checkInvalidView("set")
    checkInvalidView("add")
    checkInvalidView("add-at")
    checkInvalidView("remove")
    checkInvalidView("removeAt")
    checkInvalidView("clear")
    checkInvalidView("iterator")
    checkInvalidView("listIterator")
    checkInvalidView("listIterator-at")
    checkInvalidView("subList")
    checkInvalidView("isEmpty")
    checkInvalidView("contains")
    checkInvalidView("for")

    val backing = mutableListOf(10, 20, 30, 40, 50)
    val parent = backing.subList(1, 4)
    val child = parent.subList(1, 2)
    val sibling = backing.subList(0, 1)
    backing[1] = 21
    child[0] = 31
    println(parent)
    child.add(99)
    println(backing)
    println(parent)
    println(child)
    child.removeAt(0)
    println(backing)
    println(parent)
    println(child)
    try {
        println(sibling.size)
    } catch (e: ConcurrentModificationException) {
        println("CME: sibling")
    }
    parent.add(100)
    try {
        println(child.size)
    } catch (e: ConcurrentModificationException) {
        println("CME: child")
    }

    val iteratorBase = mutableListOf(1, 2, 3)
    val iterator = iteratorBase.subList(0, 2).iterator()
    iteratorBase.removeAt(0)
    try {
        println(iterator.next())
    } catch (e: ConcurrentModificationException) {
        println("CME: existing iterator")
    }

    val restored = mutableListOf(1, 2, 3)
    val empty = restored.subList(1, 1)
    restored.removeAt(0)
    restored.add(4)
    try {
        try {
            println(empty.size)
        } finally {
            println("finally")
        }
    } catch (e: ConcurrentModificationException) {
        println("CME: restored size and empty view")
    }
    val descendant = empty.subList(0, 0)
    println("created descendant of invalid view")
    try {
        println(descendant.size)
    } catch (e: ConcurrentModificationException) {
        println("CME: descendant")
    }
    try {
        println(empty[99])
    } catch (e: IndexOutOfBoundsException) {
        println("IOOBE: before modification check")
    } catch (e: ConcurrentModificationException) {
        println("wrong exception")
    }
}
