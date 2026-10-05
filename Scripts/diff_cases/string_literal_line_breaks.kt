fun main() {
    println("  indented\n  text")
    println("line\r\ntext")
    println("""  indented
  text""")
    println("value ${
        1 + 2
    }")
    println($$"  indented\n  text")
    println($$"""  indented
  text""")
    println($$"value $${
        1 + 2
    }")
}
