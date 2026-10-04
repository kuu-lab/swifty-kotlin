package golden.sema

fun arrayListReceiverMembers(list: ArrayList<String?>, elements: Collection<String?>): Any? {
    list.add("a")
    list.add(0, "b")
    list.addAll(elements)
    list.addAll(0, elements)
    list.clear()
    list.contains("a")
    list.containsAll(elements)
    list.ensureCapacity(16)
    list.equals(elements)
    list.get(0)
    list.hashCode()
    list.indexOf("a")
    list.isEmpty()
    list.iterator()
    list.lastIndexOf("a")
    list.listIterator()
    list.listIterator(0)
    list.remove("a")
    list.removeAll(elements)
    list.removeAt(0)
    list.retainAll(elements)
    list.set(0, "c")
    list.size
    list.subList(0, 1)
    list.toString()
    list.trimToSize()
    return list
}
