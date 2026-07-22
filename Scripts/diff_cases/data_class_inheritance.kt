// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
// Diagnostic cases for invalid data class inheritance (STDLIB-DATA-014)

// Case 1: Attempting to inherit from a data class - should be an error.
data class Person(val name: String, val age: Int)

class Employee(name: String, age: Int, val salary: Double) : Person(name, age)

// Case 2: Nested data class inheritance attempt.
class Container {
    data class Inner(val value: String)

    class Outer(val value: String) : Inner(value)
}

// Case 3: Multiple inheritance with a data class.
interface MultiInterface1
interface MultiInterface2

data class MultiBase(val value: String)

class Multi(val prop: Int) : MultiBase("test"), MultiInterface1, MultiInterface2

fun main() {}
