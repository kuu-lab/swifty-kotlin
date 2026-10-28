// KUU-3524: `by` class-delegation clauses accept full expressions whose
// bodies use braces: `when`, `if`/`else`, `try`/`catch`, object literals,
// and parenthesized forms. A later top-level brace still opens the class
// body, and the delegate expression is evaluated once per instance.
interface C { fun f(): String }
interface C2 { fun g(): String }
class B(val value: String) : C { override fun f() = value }

val y = B("K")
fun selector() = 2

class WhenSubject : C by when (selector()) {
    2 -> y
    else -> B("w")
}

class WhenSubjectless : C by when {
    selector() == 2 -> y
    else -> B("w")
}

class IfElse : C by if (selector() == 2) { y } else { B("i") }

class TryCatch : C by try { y } catch (e: Exception) { B("t") }

class ObjectLiteral : C by object : C { override fun f() = "O" }

class Parenthesized : C by (if (selector() == 2) y else B("p"))

class WhenThenBody : C by when (selector()) {
    2 -> y
    else -> y
} {
    fun extra() = "E"
}

class MultiEntry : C2, C by when (selector()) {
    2 -> y
    else -> y
} {
    override fun g() = "G"
}

fun main() {
    println(WhenSubject().f())
    println(WhenSubjectless().f())
    println(IfElse().f())
    println(TryCatch().f())
    println(ObjectLiteral().f())
    println(Parenthesized().f())
    println(WhenThenBody().f() + ":" + WhenThenBody().extra())
    println(MultiEntry().f() + ":" + MultiEntry().g())
}
