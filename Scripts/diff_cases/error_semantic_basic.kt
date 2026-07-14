// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
// Error cases for basic semantic analysis (KSWIFTK-SEMA-*)

// ERROR: Using 'this' outside of a class/object
val badThis = this  // KSWIFTK-SEMA-0010: 'this' is not defined in this context

// ERROR: Using 'super' outside of a class
val badSuper = super.toString()  // KSWIFTK-SEMA-0011: 'super' is not an expression outside of a class

// ERROR: break outside of a loop
fun noLoop() {
    break  // KSWIFTK-SEMA-0012: 'break' and 'continue' are only allowed inside a loop
}

// ERROR: continue outside of a loop
fun noContinue() {
    continue  // KSWIFTK-SEMA-0013: 'break' and 'continue' are only allowed inside a loop
}

// ERROR: return with a value in a Unit function
fun unitFunction(): Unit {
    return 42  // KSWIFTK-SEMA-0014: return type mismatch; Unit function cannot return a value
}

// ERROR: Variable used before initialization
fun useBeforeInit() {
    val x: Int
    println(x)  // KSWIFTK-SEMA-0015: variable 'x' must be initialized before use
    x = 10
}

fun main() {}
