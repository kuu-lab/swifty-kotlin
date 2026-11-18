// KUU-4594: a `List<Int>` heap-polluted into `List<String>` through an
// unchecked generic cast must throw ClassCastException when an element is read
// through a typed member call (`[0]` / `get`) or claimed by the for-loop
// iterator as String — not silently print `null`. Valid generic reads and
// primitive-element iteration must keep working.
fun main() {
    val li: Any = listOf(1, 2, 3)
    @Suppress("UNCHECKED_CAST")
    val unchecked = li as List<String>

    println("size:${unchecked.size}")
    println("index:" + try { val s: String = unchecked[0]; "ok:$s" } catch (e: ClassCastException) { "CCE" })
    println("get:" + try { val s: String = unchecked.get(0); "ok:$s" } catch (e: ClassCastException) { "CCE" })
    println("iter:" + try { var acc = ""; for (s in unchecked) { acc += s }; "ok:$acc" } catch (e: ClassCastException) { "CCE" })

    // Valid String lists keep working through the same paths.
    val ok: Any = listOf("a", "b")
    @Suppress("UNCHECKED_CAST")
    val checked = ok as List<String>
    println("valid-index:${checked[0]}")
    println("valid-get:${checked.get(1)}")
    println("valid-iter:" + try { var acc = ""; for (s in checked) { acc += s }; "ok:$acc" } catch (e: ClassCastException) { "CCE" })

    // Primitive element iteration is unaffected by the reference-type claim.
    var sum = 0
    for (i in listOf(1, 2, 3)) { sum += i }
    println("int-sum:$sum")
}
