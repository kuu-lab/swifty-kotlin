import java.util.*
import java.util.stream.*

fun main() {
    val l = ArrayList(listOf(1, 2, 3))
    println(l.stream().findFirst().get())
    println(l.stream().findAny().get())
    println(l.stream().max(naturalOrder()).get())
    println(l.stream().min(naturalOrder()).get())
    println(l.stream().reduce { a: Int, b: Int -> a + b }.get())
    println(l.stream().toArray().contentToString())
    println(l.stream().iterator().next())
    println(Stream.ofNullable(5).count())
    println(Stream.ofNullable<Int>(null).count())
    println(Stream.concat(Stream.of(1, 2), Stream.of(3)).toList())
    println(Stream.generate { 7 }.limit(3).toList())
    val b = Stream.builder<Int>().add(1).add(2).build()
    println(b.toList())
    println(l.stream().map { "n$it" }.collect(Collectors.joining(",")))
    println(l.stream().collect(Collectors.summingInt { it * 2 }))
    val tm = l.stream().collect(Collectors.toMap<Int, Int, String>({ it }, { "v$it" }))
    println(tm[1]); println(tm[2]); println(tm[3])
    val gb = l.stream().collect(Collectors.groupingBy<Int, Int> { it % 2 })
    println(gb[0]); println(gb[1])
}
