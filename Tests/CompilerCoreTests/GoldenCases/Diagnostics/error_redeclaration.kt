// Error cases for redeclaration errors (KSWIFTK-SEMA-*)

// ERROR: Duplicate top-level function with same signature
fun duplicate(): Int = 1
fun duplicate(): Int = 2  // KSWIFTK-SEMA-0001: duplicate JVM-erased callable declaration in the same package scope

// ERROR: Duplicate top-level property
val duplicateProp = "first"
val duplicateProp = "second"  // KSWIFTK-SEMA-0001: duplicate declaration in the same package scope (duplicateProp)

// ERROR: Duplicate class name in same scope
class SameName
class SameName  // KSWIFTK-SEMA-0001: duplicate declaration in the same package scope (SameName)

// ERROR: Local variable redeclaration in same scope
fun localRedecl() {
    val x = 1
    val x = 2  // NOT YET DIAGNOSED: kotlinc errors with 'conflicting declarations'; KSwiftK emits nothing
    println(x)
}

// NOT an error: a local shadowing a parameter is shadowing, not redeclaration
fun paramClash(x: Int) {
    val x = 10  // no diagnostic, matching kotlinc, which compiles this silently
    println(x)
}

// ERROR: Duplicate enum entry
enum class Status {
    ACTIVE,
    INACTIVE,
    ACTIVE  // KSWIFTK-SEMA-0001: duplicate declaration in the same package scope (ACTIVE)
}

fun main() {}
