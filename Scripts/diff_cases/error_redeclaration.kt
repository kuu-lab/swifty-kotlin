// Error cases for redeclaration errors (KSWIFTK-SEMA-*)

// ERROR: Duplicate top-level function with same signature
fun duplicate(): Int = 1
fun duplicate(): Int = 2  // KSWIFTK-SEMA-0050: conflicting declarations: duplicate()

// ERROR: Duplicate top-level property
val duplicateProp = "first"
val duplicateProp = "second"  // KSWIFTK-SEMA-0050: conflicting declarations: duplicateProp

// ERROR: Duplicate class name in same scope
class SameName
class SameName  // KSWIFTK-SEMA-0050: conflicting declarations: SameName

// ERROR: Local variable redeclaration in same scope
fun localRedecl() {
    val x = 1
    val x = 2  // KSWIFTK-SEMA-0051: conflicting declarations: x
    println(x)
}

// ERROR: Parameter name clashes with local variable
fun paramClash(x: Int) {
    val x = 10  // KSWIFTK-SEMA-0052: variable 'x' is already defined in the scope
    println(x)
}

// ERROR: Duplicate enum entry
enum class Status {
    ACTIVE,
    INACTIVE,
    ACTIVE  // KSWIFTK-SEMA-0050: conflicting declarations: ACTIVE
}

fun main() {}
