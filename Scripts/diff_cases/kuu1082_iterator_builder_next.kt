// KUU-1082: .next() on iterator {} builder results
// (KIR verifier: expression read but never defined; exhaustion must throw
// a catchable NoSuchElementException, not panic)
fun main() {
    println(iterator { yield(10) }.next())

    val it: Iterator<Int> = iterator { yield(10) }
    println(it.next())

    val it2 = iterator { yield(1); yield(2) }
    while (it2.hasNext()) {
        println(it2.next())
    }

    val it3 = iterator { yield(9) }
    println(it3.next())
    try {
        it3.next()
        println("no throw")
    } catch (e: NoSuchElementException) {
        println("caught NSEE")
    }
}
