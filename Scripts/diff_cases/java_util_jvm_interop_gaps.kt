// KUU-4358: bundled java.util/java.lang gaps — Objects null-default
// helpers, java.util.Comparator ordering factories, Scanner.delimiter(),
// java.lang.annotation.ElementType and java.lang.Thread.State.
import java.util.Objects
import java.util.Comparator
import java.util.Scanner
import java.util.EnumSet
import java.lang.annotation.ElementType
import java.lang.Thread

fun main() {
    println(Objects.requireNonNullElse(null, 9))
    println(Objects.requireNonNullElse(3, 9))
    println(Objects.requireNonNullElseGet<Int?>(null) { 7 })
    try {
        Objects.requireNonNullElse<Any?>(null, null)
    } catch (e: NullPointerException) {
        println("NPE")
    }
    try {
        Objects.requireNonNullElseGet<String?>(null) { null }
    } catch (e: NullPointerException) {
        println("NPE2")
    }

    println(Comparator.naturalOrder<Int>().compare(1, 2))
    println(Comparator.naturalOrder<Int>().compare(2, 1))
    println(Comparator.reverseOrder<Int>().compare(1, 2))
    println(Comparator.reverseOrder<String>().compare("a", "b"))

    val sc = Scanner("a,b").useDelimiter(",")
    println(sc.delimiter().pattern())
    println(Scanner("x  y").delimiter().pattern())

    println(EnumSet.allOf(ElementType::class.java).size)
    println(ElementType.TYPE.name)
    println(Thread.State.NEW.ordinal)
    println(Thread.State.values().size)
    println(Thread.State.RUNNABLE.name)
}
