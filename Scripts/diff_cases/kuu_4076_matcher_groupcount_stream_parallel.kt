import java.util.regex.Pattern
import java.util.stream.Collectors
import java.util.stream.IntStream
import java.util.stream.Stream

fun main() {
    // KUU-4076: Matcher.groupCount() reports the pattern's capturing groups
    // without requiring a match, and group(i) resolves alongside it.
    val matcher = Regex("(.)(.)").toPattern().matcher("ab")
    println(matcher.groupCount())
    println(matcher.matches())
    println(List<String>(matcher.groupCount()) { matcher.group(it + 1) })

    // Non-capturing forms, escapes, classes, and quoted spans are skipped.
    println(Pattern.compile("(?:x)(a)").matcher("xa").groupCount())
    println(Pattern.compile("(?<n>a)(b)").matcher("ab").groupCount())
    println(Pattern.compile("(?=x)(a)").matcher("xa").groupCount())
    println(Pattern.compile("(?<=x)(a)").matcher("xa").groupCount())
    println(Pattern.compile("a\\(b").matcher("a(b").groupCount())
    println(Pattern.compile("[(]x").matcher("(x").groupCount())
    println(Pattern.compile("\\Q(a)\\E(b)").matcher("(a)b").groupCount())
    println(Pattern.compile("(?i)a(b)").matcher("Ab").groupCount())
    println(Pattern.compile("a # ignored (group)\nb(c)", Pattern.COMMENTS).matcher("abc").groupCount())
    val literal = Pattern.compile("(a)", Pattern.LITERAL).matcher("(a)")
    println(literal.matches())
    println(literal.groupCount())

    // KUU-4076: Stream.parallel()/sequential()/isParallel()/unordered() and
    // Collection.parallelStream() resolve and evaluate sequentially.
    println(listOf(1, 2, 3).stream().parallel().collect(Collectors.toList()))
    println(listOf("a", "b").parallelStream().collect(java.util.stream.Collectors.toList()))
    println(listOf(1).stream().parallel().isParallel())
    println(listOf(1).stream().parallel().sequential().isParallel())
    println(IntStream.of(1, 2, 3).parallel().sum())
    println(Stream.of(1, 2).unordered().count())
}
