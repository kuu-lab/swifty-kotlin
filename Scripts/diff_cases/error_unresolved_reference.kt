// Error cases for unresolved references (KSWIFTK-SEMA-*)

fun main() {
    // ERROR: Reference to undefined variable
    println(undeclaredVariable)  // KSWIFTK-SEMA-0001: unresolved reference: undeclaredVariable

    // ERROR: Call to undefined function
    val result = nonExistentFunction(1, 2)  // KSWIFTK-SEMA-0001: unresolved reference: nonExistentFunction

    // ERROR: Access to member of unknown type
    val obj = SomeUndefinedClass()  // KSWIFTK-SEMA-0001: unresolved reference: SomeUndefinedClass
    obj.doSomething()

    // ERROR: Using undefined type as annotation
    @UndefinedAnnotation
    fun annotated() {}  // KSWIFTK-SEMA-0001: unresolved reference: UndefinedAnnotation

    // ERROR: Reference to undefined companion member
    val value = MyClass.UNDEFINED_CONST  // KSWIFTK-SEMA-0001: unresolved reference: UNDEFINED_CONST
}

class MyClass {
    companion object {
        const val DEFINED_CONST = 1
    }
}
