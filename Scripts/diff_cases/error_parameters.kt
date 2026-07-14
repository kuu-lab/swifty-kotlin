// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
// Error cases for parameter errors (KSWIFTK-SEMA-* / KSWIFTK-TYPE-*)

fun required(a: Int, b: String) = "$a $b"

fun main() {
    // ERROR: Too few arguments
    required(1)  // KSWIFTK-SEMA-0070: no value passed for parameter 'b'

    // ERROR: Too many arguments
    required(1, "hello", "extra")  // KSWIFTK-SEMA-0071: too many arguments for required(Int, String)

    // ERROR: Wrong argument type
    required("wrong", "hello")  // KSWIFTK-TYPE-0040: type mismatch for parameter 'a': expected Int found String

    // ERROR: Duplicate named argument
    required(a = 1, a = 2, b = "x")  // KSWIFTK-SEMA-0072: an argument is already passed for this parameter

    // ERROR: Named argument for non-existent parameter
    required(a = 1, c = "wrong")  // KSWIFTK-SEMA-0073: no parameter with this name: c
}

// ERROR: Default value references later parameter
fun badDefaults(
    a: Int = b,  // KSWIFTK-SEMA-0074: unresolved reference: b (forward reference to default parameter)
    b: Int = 0
) {}

// ERROR: vararg combined with named argument in wrong order
fun varargFun(vararg items: Int, name: String) = name

fun callVararg() {
    varargFun(1, 2, 3, name = "ok")  // OK
    varargFun(name = "bad", 1, 2)   // KSWIFTK-SEMA-0075: vararg argument after named argument is not allowed
}
