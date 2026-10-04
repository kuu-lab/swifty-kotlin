fun main() {
    println(String.format("%h", "abc"))
    println(String.format("%h %h", "abc", null))
    println(String.format("%H", "abc"))
    println(String.format("%8h", "abc"))
    println(String.format("%a", 1.5))
    println(String.format("%s %h", 42, 42))
    println(String.format("%tQ", 1700000000123L))
    println(String.format("%ts", 1700000000123L))
}
