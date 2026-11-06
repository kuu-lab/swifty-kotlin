import java.util.Optional
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.Supplier

fun doubleIt(x: Int): Int = x * 2
fun intToOptional(x: Int): Optional<Int> = Optional.of(x * 2)

fun main() {
    // KUU-3995: bundled java.util.Optional was missing flatMap and the
    // Java 9+ API surface, and its functional parameters used Kotlin
    // function types instead of the java.util.function SAM types the
    // JDK declares.
    println(Optional.of(3).flatMap { Optional.of(it * 2) }.get())

    println(Optional.of(3).map { it * 2 }.get())
    println(Optional.of(3).map(Function<Int, Int> { it + 1 }).get())
    println(Optional.of(3).map(::doubleIt).get())
    println(Optional.of(3).filter { it > 2 }.get())
    println(Optional.of(1).filter(Predicate<Int> { it > 2 }).isEmpty)
    println(Optional.empty<Int>().map { it * 2 }.isEmpty)
    println(Optional.empty<Int>().filter { true }.isEmpty)

    println(Optional.of(3).flatMap(::intToOptional).get())
    println(Optional.of(3).flatMap(Function<Int, Optional<Int>> { intToOptional(it) }).get())
    println(Optional.empty<Int>().flatMap { Optional.of(it * 2) }.isEmpty)
    println(Optional.of(3).flatMap { Optional.empty<Int>() }.isEmpty)

    Optional.of(4).ifPresent { println("present:$it") }
    Optional.empty<Int>().ifPresent { println("never") }
    Optional.of(4).ifPresent(Consumer<Int> { println("c:$it") })
    Optional.of(4).ifPresentOrElse({ println("p:$it") }, { println("empty") })
    Optional.empty<Int>().ifPresentOrElse({ println("never:$it") }, { println("was empty") })
    Optional.of(4).ifPresentOrElse(Consumer<Int> { println("cp:$it") }, Runnable { println("ce") })
    Optional.empty<Int>().ifPresentOrElse(Consumer<Int> { println("cn:$it") }, Runnable { println("ce2") })

    println(Optional.of(1).or { Optional.of(9) }.get())
    println(Optional.empty<Int>().or { Optional.of(9) }.get())
    println(Optional.empty<Int>().or { Optional.empty<Int>() }.isEmpty)
    println(Optional.empty<Int>().or(Supplier { Optional.of(11) }).get())
    println(Optional.of(5).orElse(0))
    println(Optional.empty<Int>().orElse(7))
    println(Optional.empty<Int>().orElseGet { 42 })
    println(Optional.of(5).orElseGet(Supplier<Int> { 0 }))
    println(Optional.of(5).orElseThrow())
    try {
        Optional.empty<Int>().orElseThrow()
    } catch (e: NoSuchElementException) {
        println("noSuch:${e.message}")
    }
    try {
        Optional.empty<Int>().orElseThrow { IllegalStateException("custom") }
    } catch (e: IllegalStateException) {
        println("custom:${e.message}")
    }
    println(Optional.of(5).orElseThrow { IllegalStateException("x") })

    println(Optional.of(7).stream().count())
    println(Optional.empty<Int>().stream().count())
    println(Optional.of(7).stream().toList())
    println(Optional.of(8).stream().map(Function<Int, Int> { it + 1 }).toList())

    println(Optional.of(1) == Optional.of(1))
    println(Optional.of(1) == Optional.of(2))
    println(Optional.of(1).hashCode())
    println(Optional.empty<Int>().hashCode())
    println("${Optional.of("x")}")
    println("${Optional.empty<Int>()}")

    val o = Optional.of(5)
    println(o.isPresent)
    println(o.isPresent())
    println(o.isEmpty)
    println(Optional.empty<Int>().isPresent)
}
