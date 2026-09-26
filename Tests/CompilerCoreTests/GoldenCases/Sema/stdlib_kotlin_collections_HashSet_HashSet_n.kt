package golden.sema

fun hashSetReceiverMembers(set: HashSet<String?>, elements: Collection<String?>): Any? {
    set.add("a")
    set.addAll(elements)
    set.clear()
    set.contains("a")
    set.isEmpty()
    set.iterator()
    set.remove("a")
    set.removeAll(elements)
    set.retainAll(elements)
    set.size
    return set
}
