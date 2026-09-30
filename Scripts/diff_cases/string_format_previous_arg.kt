fun main() {
    println(String.format("%s %<s", "x"))
    println(String.format("%d|%03d|%<d", 7, 8))
    println(String.format("%1\$s %<s", "a"))
    println("%s %s %<s %<s".format("a", "b", "c"))
    println("%s %<s %s".format("a", "b"))
    println("%2\$s %s %<s".format("a", "b", "c"))
    println("%d %<05d %<d".format(42))
    println("%s %<d".format(7))
    println("%s|%<5s|%-<5s".format("x"))
    println("%s %2\$<s".format("a", "b"))
}
