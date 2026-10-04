package golden.sema

fun exerciseIndexedValueMembers() {
    val entry: IndexedValue<String> = IndexedValue(7, "x")
    println(entry.index)
    println(entry.value)
    println(entry.component1())
    println(entry.component2())
    println(entry.copy())
    println(entry.copy(index = 8))
    println(entry.copy(value = "y"))
    println(entry == IndexedValue(7, "x"))
    println(entry.hashCode() == IndexedValue(7, "x").hashCode())
    println(entry.toString())
}
