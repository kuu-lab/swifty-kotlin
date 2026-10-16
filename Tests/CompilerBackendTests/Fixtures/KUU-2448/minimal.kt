class A {
    infix fun infix(s: String): String = "O" + s
}
fun box(): String = A() infix "K"
