@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Keep these related scenarios in one XCTest method. CodegenBackendIntegrationTests
    // is already a large XCTestCase, and Swift's generated discovery array can
    // otherwise exceed the type-checker time limit when several methods are added.
    func testAnyAndNumberTypedLocalsAreBoxedCorrectly() throws {
        // Reported bug: `.localDecl` aliased a local's storage directly to its
        // initializer expression's own KIRExprID, so an `Any`-declared local kept
        // the initializer's narrower arena type (e.g. Int) forever. Neither the
        // initial binding nor later `.localAssign` copies ever boxed the value,
        // so `is` checks against the raw unboxed payload were unreliable.
        try assertKotlinOutput(
            """
            fun main() {
                var i: Any = 42
                i = 99L
                println(i is Long)
                println(i is Int)
                println(i)
            }
            """,
            moduleName: "AnyTypedLocalVarReassignment",
            expected: "true\nfalse\n99\n"
        )

        // Generalization: the bug did not require a reassignment at all. Even a
        // single `val` binding must report the correct dynamic type.
        try assertKotlinOutput(
            """
            fun main() {
                val i: Any = 42
                println(i is Int)
                println(i is Long)
            }
            """,
            moduleName: "AnyTypedLocalValWithoutReassignment",
            expected: "true\nfalse\n"
        )

        // An Any-typed local re-declared through multiple concrete types in
        // sequence must have each reassignment tracked independently.
        try assertKotlinOutput(
            """
            fun main() {
                var a: Any = "hello"
                println(a is String)
                a = 42
                println(a is Int)
                println(a is String)
                a = 3.14
                println(a is Double)
                println(a is Int)
            }
            """,
            moduleName: "AnyTypedLocalVarMultipleReassignments",
            expected: "true\ntrue\nfalse\ntrue\nfalse\n"
        )

        // A local declared without an initializer hits `.localAssign`'s
        // "no existing storage yet" branch on its first assignment.
        try assertKotlinOutput(
            """
            fun main() {
                var i: Any
                i = 42
                println(i is Int)
                println(i is Long)
            }
            """,
            moduleName: "AnyTypedLocalVarWithoutInitializer",
            expected: "true\nfalse\n"
        )

        // Generalization beyond `Any`: a wider reference type such as Number
        // must go through the same widening/boxing path.
        try assertKotlinOutput(
            """
            fun main() {
                var n: Number = 42
                println(n is Int)
                println(n is Long)
                n = 99L
                println(n is Long)
                println(n is Int)
                println(n)
            }
            """,
            moduleName: "NumberTypedLocalVarReassignment",
            expected: "true\nfalse\ntrue\nfalse\n99\n"
        )
    }
}
