@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3904: reading a member property whose backing field is not yet
/// initialized reports `KSWIFTK-SEMA-0031` ("Variable must be initialized
/// before use") instead of silently observing a zeroed or null field at
/// runtime — kotlinc rejects the same programs with
/// `variable 'x' must be initialized`.
@Suite
struct MemberPropertyReadBeforeInitializationTests {
    static let rejected = [
        // Property initializer reading a property declared later.
        "class Box { val x = TARGET; val value = 1 }",
        "class Box { val x = TARGET; var value = 1 }",
        "class Box { val x = this.TARGET; val value = 1 }",
        "class Box { val x = this@Box.TARGET; val value = 1 }",
        // Invoking a function-typed property declared later.
        "class Box { val x = TARGET(); val value: () -> Int = { 3 } }",
        "class Box { val x = this.TARGET(); val value: () -> Int = { 3 } }",
        // A custom accessor that touches `field` still reads real storage.
        "class Box { val x = TARGET; val value: Int get() = field }",
        // Read before a definite assignment inside an init block.
        "class Box { var value: Int; init { val z = TARGET; value = 1 } }",
        // Init block running before the property's own initializer.
        "class Box { init { val z = TARGET }; var value = 1 }",
        // Secondary constructor bodies follow the same definite-init flow.
        "class Box { var value: Int; constructor() { val z = TARGET; value = 1 } }",
        // A compound assignment reads the field before writing it back.
        "class Box { var value: Int; init { TARGET += 1 } }",
        "class Box { var value: Int; init { this.TARGET += 1 } }",
        // Virtual dispatch still reads this class's unwritten backing field.
        "open class Box { val x = TARGET; open val value = 1 }",
        "open class Base { open val value = 1 }; class Box : Base() { val x = TARGET; override val value = 2 }",
        // A property's own initializer reading itself.
        "class Box { val value: Int = TARGET }",
        // Objects and local classes follow the same initialization order.
        "object Box { val x = TARGET; val value = 1 }",
        "fun make() { class Box { val x = TARGET; val value = 1 } }",
    ]

    static let accepted = [
        // Reading a property whose initializer already ran.
        "class Box { val value = 1; val x = TARGET + 1 }",
        // Primary-constructor properties are initialized before the body.
        "class Box(val value: Int) { val x = TARGET }",
        // Member functions may be forward-referenced, even when their body
        // reads a later-declared property (kotlinc does not analyze calls).
        "class Box { val x = pick(); val value = 1; fun pick() = 2 }",
        "class Box { val x = pick(); val value = 1; fun pick() = TARGET }",
        // Lambdas run after construction completes, even as inline arguments.
        "class Box { val cb = { TARGET }; val value = 1 }",
        """
        inline fun <T> runIt(block: () -> T): T = block()
        class Box { var value: Int; init { runIt { val z = TARGET }; value = 1 } }
        """,
        // Accessor-only properties have no backing field to read.
        "class Box { val x = TARGET; val value: Int get() = 3 }",
        // `lateinit` deliberately defers initialization to a runtime check.
        "class Box { val x = TARGET; lateinit var value: String }",
        // `const val` reads are compile-time constants.
        "object Box { val x = TARGET; const val value = 1 }",
        // Properties of other instances are not this instance's init state.
        "class Box { val x = other.TARGET; lateinit var other: Box; val value = 1 }",
        // Inherited fields are initialized by the super constructor first.
        "open class Base { val value = 1 }; class Box : Base() { val x = TARGET }",
        // Write-then-read inside the same init block.
        "class Box { var value: Int; init { TARGET = 1; val z = TARGET } }",
        "class Box { var value = 1; init { TARGET += 1 } }",
        // Companion members belong to a different receiver.
        "class Box { val x = TARGET; companion object { val value = 1 } }",
        // `+=` on an initialized `val` resolved to `plusAssign` mutates the
        // object in place; it is not a reassignment of the field.
        "class Acc { operator fun plusAssign(x: Int) {} }; class Box { val value = Acc(); init { TARGET += 1 } }",
        "class Acc { operator fun plusAssign(x: Int) {} }; class Box { val value = Acc(); init { this.TARGET += 1 } }",
        "class Acc { operator fun plusAssign(x: Int) {} }; object Box { val value = Acc(); init { TARGET += 1 } }",
        "class Acc { operator fun plusAssign(x: Int) {} }; class Box { companion object { val value = Acc(); init { TARGET += 1 } } }",
    ]

    @Test(arguments: rejected)
    func rejectsUninitializedRead(source: String) throws {
        try check(
            source.replacingOccurrences(of: "TARGET", with: "value"),
            expectedReadErrors: 1
        )
    }

    @Test(arguments: accepted)
    func acceptsInitializedOrDeferredRead(source: String) throws {
        try check(
            source.replacingOccurrences(of: "TARGET", with: "value"),
            expectedReadErrors: 0
        )
    }

    // Without a `plusAssign` operator, `+=` on an initialized `val` is still
    // a reassignment.
    @Test
    func valCompoundAssignWithoutAssignOperatorStillReportsReassignment() throws {
        try withTemporaryFile(contents: "class Box { val value = 1; init { value += 1 } }") { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0014" })
        }
    }

    private func check(_ source: String, expectedReadErrors: Int) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.filter { $0.code == "KSWIFTK-SEMA-0031" }.count == expectedReadErrors,
                "\(source): \(errors)"
            )
            if expectedReadErrors == 0 { #expect(errors.isEmpty, "\(source): \(errors)") }
        }
    }
}
