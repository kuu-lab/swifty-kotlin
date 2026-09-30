fun main() {
    val list = ArrayList<String?>()
    println(list.isEmpty())
    println(list.size)

    // Capacity hints are contract-only no-ops; the list stays usable.
    list.ensureCapacity(16)
    list.trimToSize()
    println(list.size)

    println(list.add("a"))
    list.add(0, "b")
    println(list.addAll(listOf("c", "d")))
    println(list.addAll(1, listOf("x")))
    println(list.size)
    println(list.toString())
    println(list)

    println(list.get(0))
    println(list[2])
    println(list.indexOf("d"))
    println(list.lastIndexOf("b"))
    println(list.indexOf("missing"))
    println(list.contains("x"))
    println(list.containsAll(listOf("b", "d")))

    println(list.set(0, "B"))
    println(list.removeAt(1))
    println(list.size)

    println(list.remove("d"))
    println(list.remove("missing"))
    println(list.removeAll(listOf("c")))
    list.add("z")
    println(list.retainAll(listOf("B", "a")))
    println(list.toString())

    // Structural equality/hashCode agree across list implementations.
    val same = ArrayList(list)
    println(list.equals(same))
    println(list == same)
    println(list.hashCode() == same.hashCode())
    val asMutable: MutableList<String?> = same
    println(list == asMutable)
    println(list.equals(hashSetOf("B", "a")))
    println(list.equals("not a list"))
    println(same.equals(same))

    val iter = list.iterator()
    println(iter.hasNext())
    println(iter.next())
    val listIter = list.listIterator()
    println(listIter.next())
    println(listIter.nextIndex())
    println(listIter.hasPrevious())
    println(listIter.previousIndex())
    println(listIter.previous())
    println(list.listIterator(1).next())

    val sub = list.subList(0, 1)
    println(sub.size)
    println(sub.get(0))

    list.clear()
    println(list.isEmpty())
    println(list.size)
}
