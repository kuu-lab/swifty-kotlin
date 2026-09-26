// Recursive type aliases must be rejected at declaration, not only at expansion.

typealias A = B
typealias B = A

fun main() {}
