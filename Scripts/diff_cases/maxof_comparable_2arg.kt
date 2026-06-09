// STDLIB-COMP-FN-005: maxOf 関数（Comparable版、2引数）

fun main() {
    // String は Comparable<String> を実装しているため generic 版が解決される
    val s1 = maxOf("apple", "banana")
    println(s1)

    val s2 = maxOf("zoo", "apple")
    println(s2)

    val s3 = maxOf("abc", "abc")
    println(s3)
}
