import java.util.function.DoublePredicate
import java.util.function.IntFunction
import java.util.function.IntPredicate
import java.util.function.Predicate
import java.util.function.ToDoubleFunction

fun main() {
    val charsBuilder = StringBuilder("A")
    var intCalls = 0
    var objectCalls = 0
    var objectFilterCalls = 0
    var doubleCalls = 0
    var doubleFilterCalls = 0
    val charsPipeline = (charsBuilder as CharSequence).chars()
        .filter(IntPredicate { intCalls++; it > 65 })
        .mapToObj(IntFunction<Int> { objectCalls++; it })
        .filter(Predicate<Int> { objectFilterCalls++; it > 0 })
        .mapToDouble(ToDoubleFunction<Int> { doubleCalls++; it.toDouble() })
        .filter(DoublePredicate { doubleFilterCalls++; it >= 66.0 })
    charsBuilder.append("BC")
    println("chars-before=$intCalls,$objectCalls,$objectFilterCalls,$doubleCalls,$doubleFilterCalls")
    println("chars-first=" + charsPipeline.findFirst().getAsDouble())
    println("chars-after=$intCalls,$objectCalls,$objectFilterCalls,$doubleCalls,$doubleFilterCalls")

    val pointsBuilder = StringBuilder("A")
    var pointsCalls = 0
    val pointsPipeline = (pointsBuilder as CharSequence).codePoints()
        .filter(IntPredicate { pointsCalls++; it > 65 })
        .mapToObj(IntFunction<Int> { it })
        .filter(Predicate<Int> { it >= 66 })
        .mapToDouble(ToDoubleFunction<Int> { it.toDouble() })
        .filter(DoublePredicate { it > 0.0 })
    pointsBuilder.append("😀B")
    println("points-before=$pointsCalls")
    println("points-sum=" + pointsPipeline.sum())
    println("points-after=$pointsCalls")
}
