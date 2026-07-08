@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Reported bug: `.localDecl` aliased a local's storage directly to its
    // initializer expression's own KIRExprID, so an `Any`-declared local kept
    // the initializer's narrower arena type (e.g. Int) forever. Neither the
    // initial binding nor later `.localAssign` copies ever boxed the value,
    // so `is` checks against the raw unboxed payload were unreliable.
    func testAnyTypedLocalVarReassignmentIsCheckedCorrectly() throws {
        let source = """
        fun main() {
            var i: Any = 42
            i = 99L
            println(i is Long)
            println(i is Int)
            println(i)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AnyTypedLocalVarReassignment",
            expected: "true\nfalse\n99\n"
        )
    }

    // Generalization: the bug did not require a reassignment at all. Even a
    // single `val` binding never boxed the initializer, so this must also
    // report the correct dynamic type.
    func testAnyTypedLocalValIsCheckedCorrectlyWithoutReassignment() throws {
        let source = """
        fun main() {
            val i: Any = 42
            println(i is Int)
            println(i is Long)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AnyTypedLocalValWithoutReassignment",
            expected: "true\nfalse\n"
        )
    }

    // Generalization: an Any-typed local re-declared through multiple concrete
    // types in sequence must have each reassignment tracked independently.
    func testAnyTypedLocalVarTracksTypeAcrossMultipleReassignments() throws {
        let source = """
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
        """
        try assertKotlinOutput(
            source,
            moduleName: "AnyTypedLocalVarMultipleReassignments",
            expected: "true\ntrue\nfalse\ntrue\nfalse\n"
        )
    }

    // Same bug, different entry point: a local declared without an initializer
    // hits `.localAssign`'s "no existing storage yet" branch on its first
    // assignment, which aliased the assigned value's own narrower arena type
    // instead of widening to the symbol's declared type.
    func testAnyTypedLocalVarWithoutInitializerIsCheckedCorrectlyOnFirstAssignment() throws {
        let source = """
        fun main() {
            var i: Any
            i = 42
            println(i is Int)
            println(i is Long)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "AnyTypedLocalVarWithoutInitializer",
            expected: "true\nfalse\n"
        )
    }

    // Generalization beyond `Any`: any declared reference type wider than the
    // initializer's own type (e.g. the `Number` interface) must go through
    // the same widening/boxing path.
    func testNumberTypedLocalVarReassignmentIsCheckedCorrectly() throws {
        let source = """
        fun main() {
            var n: Number = 42
            println(n is Int)
            println(n is Long)
            n = 99L
            println(n is Long)
            println(n is Int)
            println(n)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumberTypedLocalVarReassignment",
            expected: "true\nfalse\ntrue\nfalse\n99\n"
        )
    }
}
