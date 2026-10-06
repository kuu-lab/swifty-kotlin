// KUU-1312: Check both inferred and erased view types.
fun checkView(value: Any) {
    println(value is MutableList<*>)
    println(value is RandomAccess)
    println(value is List<*>)
    println(value is Collection<*>)
    println(value is Iterable<*>)
    println(value is ArrayList<*>)
}

fun main() {
    val list = mutableListOf(1, 2, 3, 4)
    val sub = list.subList(1, 3)
    println(sub is MutableList<*>)
    println(sub is RandomAccess)
    checkView(sub)
    checkView(sub.subList(0, 1))
    sub[0] = 20
    ((sub as Any) as MutableList<Int>).add(30)
    println(list)
    val reversed = list.asReversed()
    println(reversed is MutableList<*>)
    println(reversed is RandomAccess)
    checkView(reversed)
    checkView(reversed.subList(0, 1))
    val mutableReversed = (reversed as Any) as MutableList<Int>
    mutableReversed[0] = 40
    reversed.add(0, 50)
    println(list)
    val readOnly: List<Int> = list
    checkView(readOnly.asReversed())
    checkView(readOnly.subList(0, 1))
    val deque = ArrayDeque<Int>()
    deque.add(1)
    deque.add(2)
    checkView(deque.subList(0, 1))
    checkView(deque.asReversed())
}
