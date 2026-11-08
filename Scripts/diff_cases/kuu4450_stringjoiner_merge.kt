import java.util.StringJoiner

fun main() {
    // ticket repro: different delimiters -> other's content joins with ITS delimiter
    val sj = StringJoiner(", ")
    sj.add("a"); sj.add("b")
    val sj2 = StringJoiner(",", "[", "]")
    sj2.add("x"); sj2.add("y")
    println(sj.merge(sj2).toString())

    // same delimiter still collapses to one element
    val s1 = StringJoiner("|").add("p").add("q")
    val s2 = StringJoiner("|").add("r").add("s")
    println(s1.merge(s2).toString())

    // single-element other merges as that element
    val t1 = StringJoiner("-").add("m")
    val t2 = StringJoiner("-").add("n")
    println(t1.merge(t2).toString())

    // empty other is a no-op, even with emptyValue set
    val e1 = StringJoiner(",").add("keep")
    val e2 = StringJoiner(",").setEmptyValue("EMPTY")
    println(e1.merge(e2).toString())

    // merging into an empty jointer with emptyValue: content wins over emptyValue
    val v1 = StringJoiner(",").setEmptyValue("EMPTY")
    val v2 = StringJoiner("+", "<", ">").add("i").add("j")
    println(v1.merge(v2).toString())

    // other remains usable and its toString is unchanged after merge
    println(sj2.toString())
    sj2.add("z")
    println(sj2.toString())

    // length() reflects merged content
    val l1 = StringJoiner(", ")
    l1.merge(StringJoiner(",", "[", "]").add("x").add("y"))
    println(l1.length())

    // three-way merge chains
    val c1 = StringJoiner(";").add("1")
    c1.merge(StringJoiner(".").add("2").add("3"))
    c1.merge(StringJoiner("/").add("4"))
    println(c1.toString())
}
