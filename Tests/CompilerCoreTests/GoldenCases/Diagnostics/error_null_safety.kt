// Error cases for null safety violations (KSWIFTK-SEMA-* / KSWIFTK-TYPE-*)

fun main() {
    // ERROR: Assigning null to non-nullable type
    val name: String = null  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (null is not a value of non-null String)

    // ERROR: Calling method on potentially null value without safe call
    val maybeNull: String? = "hello"
    val length = maybeNull.length  // KSWIFTK-SEMA-0026: Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.

    // ERROR: Passing nullable where non-nullable is required
    val nullable: Int? = 10
    requireNonNull(nullable)  // KSWIFTK-SEMA-0002: no viable overload found for call (Int? passed where Int expected)

    // NOT an error: `null!!` has type Nothing, a subtype of String
    val x: String = null!!  // no diagnostic, matching kotlinc, which compiles this silently

    // ERROR: Elvis operator result ignored when both sides are nullable
    val a: String? = null
    val b: String? = null
    val c: String = a ?: b  // KSWIFTK-TYPE-0001: type constraint could not be satisfied (String? where String expected)
}

fun requireNonNull(x: Int): Int = x
