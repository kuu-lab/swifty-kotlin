// Error cases for null safety violations (KSWIFTK-SEMA-* / KSWIFTK-TYPE-*)

fun main() {
    // ERROR: Assigning null to non-nullable type
    val name: String = null  // KSWIFTK-TYPE-0020: null cannot be a value of a non-null type String

    // ERROR: Calling method on potentially null value without safe call
    val maybeNull: String? = "hello"
    val length = maybeNull.length  // KSWIFTK-SEMA-0020: only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver

    // ERROR: Passing nullable where non-nullable is required
    val nullable: Int? = 10
    requireNonNull(nullable)  // KSWIFTK-TYPE-0021: type mismatch, expected Int found Int?

    // ERROR: Implicit not-null assertion on null literal
    val x: String = null!!  // KSWIFTK-SEMA-0021: null cannot be dereferenced

    // ERROR: Elvis operator result ignored when both sides are nullable
    val a: String? = null
    val b: String? = null
    val c: String = a ?: b  // KSWIFTK-TYPE-0022: type mismatch, expected String found String?
}

fun requireNonNull(x: Int): Int = x
