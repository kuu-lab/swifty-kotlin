// DIFF_JVM
// KUU-3983: compile-time constant string concatenation folds into the
// interned literal, so `===` observes the shared instance. Runtime
// concatenation through a non-const value keeps a fresh String and is
// not interned on either side.
const val C = "cd"
val plainVal = "ab"
object O { const val OC = "oc" }
fun box(): Any = "abc"
fun main() {
    // Constant concatenation interns to the literal.
    println("ab" + "c" === "abc")
    println("a" + 'b' === "ab")
    println("a" + 5 === "a5")
    println("a" + true === "atrue")
    println("" + null === "null")
    println("x" + "y" + "z" === "xyz")
    println("a" + 1.5 === "a1.5")
    println("a" + 1.5f === "a1.5")
    println("x" + C === "xcd")
    println("x" + O.OC === "xoc")
    println("p" + "${5}" === "p5")
    val dyn = "ab" + "c"
    println(dyn === "abc")
    println(box() === dyn)
    // Char.plus(String) is a real call on both sides, not a folded
    // String `+`, so it stays a runtime StringBuilder result.
    println('a' + "bc" === "abc")
    println('a'.plus("bc") === "abc")
    // Runtime concatenation is not interned.
    val rt = "ab"
    println(rt + "c" === "abc")
    println("x" + plainVal === "xab")
    var v = "ab"
    println("x" + v === "xab")
    println("intern" === "intern")
}
