// Error cases for parameter errors (KSWIFTK-SEMA-* / KSWIFTK-TYPE-*)

fun required(a: Int, b: String) = "$a $b"

fun main() {
    // ERROR: Too few arguments
    required(1)  // KSWIFTK-SEMA-0002: no viable overload found for call (no value passed for parameter 'b')

    // ERROR: Too many arguments
    required(1, "hello", "extra")  // KSWIFTK-SEMA-0002: no viable overload found for call (too many arguments for required(Int, String))

    // ERROR: Wrong argument type
    required("wrong", "hello")  // KSWIFTK-SEMA-0002: no viable overload found for call (parameter 'a' expects Int, found String)

    // ERROR: Duplicate named argument
    required(a = 1, a = 2, b = "x")  // KSWIFTK-SEMA-0002: no viable overload found for call (an argument is already passed for this parameter)

    // ERROR: Named argument for non-existent parameter
    required(a = 1, c = "wrong")  // KSWIFTK-SEMA-0002: no viable overload found for call (no parameter with this name: c)
}

// ERROR: Default value references later parameter
fun badDefaults(
    a: Int = b,  // KSWIFTK-SEMA-0022: unresolved reference 'b' (forward reference to default parameter)
    b: Int = 0
) {}

// ERROR: vararg combined with named argument in wrong order
fun varargFun(vararg items: Int, name: String) = name

fun callVararg() {
    varargFun(1, 2, 3, name = "ok")  // OK
    varargFun(name = "bad", 1, 2)   // KSWIFTK-SEMA-0002: no viable overload found for call (vararg argument after named argument)
}
