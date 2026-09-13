// Error cases for basic semantic analysis (KSWIFTK-SEMA-*)

// ERROR: Using 'this' outside of a class/object
val badThis = this  // KSWIFTK-SEMA-0051: 'this' is not allowed in this context

// ERROR: Using 'super' outside of a class
val badSuper = super.toString()  // KSWIFTK-SEMA-0050: 'super' is not allowed outside of a class body

// ERROR: break outside of a loop
fun noLoop() {
    break  // KSWIFTK-SEMA-0018: 'break' is only allowed inside loop bodies
}

// ERROR: continue outside of a loop
fun noContinue() {
    continue  // KSWIFTK-SEMA-0019: 'continue' is only allowed inside loop bodies
}

// ERROR: return with a value in a Unit function
fun unitFunction(): Unit {
    return 42  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (Unit function cannot return a value)
}

// ERROR: Variable used before initialization
fun useBeforeInit() {
    val x: Int
    println(x)  // KSWIFTK-SEMA-0031: variable 'x' must be initialized before use
    x = 10
}

fun main() {}
