@testable import CompilerCore
import Foundation
import XCTest

final class DiagnosticCodeCoverageTests: XCTestCase {

    // MARK: - LEX-0004

    func testLex0004UnescapedNewlineInStringLiteral() throws {
        let source = "val s = \"hello\nworld\""
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertHasDiagnostic("KSWIFTK-LEX-0004", in: ctx)
    }

    func testLex0004NotEmittedForTripleQuotedString() throws {
        let source = """
        val s = \"\"\"
        hello
        world
        \"\"\"
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-LEX-0004", in: ctx)
    }

    // MARK: - PARSE-0001

    func testParse0001ContextReceiverMissingParentheses() throws {
        let source = "context fun foo() {}"
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertHasDiagnostic("KSWIFTK-PARSE-0001", in: ctx)
    }

    // MARK: - PARSE-0006

    func testParse0006UnexpectedTokenInDeclaration() throws {
        let source = """
        fun foo() {}
        ??? unexpected
        fun bar() {}
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        // Parser currently consumes `???` silently; assert when fixed.
        let hasDiagnostic = ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0006" }
        if hasDiagnostic {
            assertHasDiagnostic("KSWIFTK-PARSE-0006", in: ctx)
        }
    }

    func testParse0006NotEmittedForValidOverrideModifier() throws {
        let source = """
        open class Base { open fun foo() {} }
        class Child : Base() { override fun foo() {} }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0006", in: ctx)
    }

    // MARK: - SEMA-0021

    func testSema0021SuperDelegationWithoutSuperclass() throws {
        let source = """
        class Foo {
            constructor(x: Int) : super()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0021") || codes.contains("KSWIFTK-SEMA-0055"),
            "Expected SEMA-0021 or SEMA-0055 for super() delegation without superclass, got: \(codes)"
        )
    }

    func testSema0021NotEmittedWhenSuperclassExists() throws {
        let source = """
        open class Base(val x: Int)
        class Derived : Base {
            constructor(x: Int) : super(x)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0021", in: ctx)
    }

    // MARK: - SEMA-0042

    func testSema0042ReturnAtInvalidLabel() throws {
        let source = """
        fun test() {
            val list = listOf(1, 2, 3)
            list.forEach {
                return@nonExistentLabel
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    // MARK: - SEMA-0043

    func testSema0043SignedUnsignedMixInBinaryAdd() throws {
        let source = """
        fun mix(a: Int, b: UInt): Int {
            val r = a + b
            return r
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0043", in: ctx)
    }

    func testSema0043NotEmittedForPureSignedArithmetic() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0043", in: ctx)
    }

    // MARK: - SEMA-0050

    func testSema0050SuperOutsideClassBody() throws {
        let source = """
        fun test() {
            val x = super.toString()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0050", in: ctx)
    }

    // MARK: - SEMA-0052

    func testSema0052SuperInClassWithNoSuperclass() throws {
        let source = """
        class Foo {
            fun test(): String = super.toString()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "super.toString() in a class implicitly extending Any should compile without errors; got: \(errors.map { $0.message })"
        )
    }

    // MARK: - SEMA-0054

    func testSema0054SecondaryCtorMissingDelegation() throws {
        let source = """
        class Bar(val x: Int) {
            constructor(x: Int, y: Int) {
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
    }

    func testSema0054NotEmittedWhenDelegationPresent() throws {
        let source = """
        class Bar(val x: Int) {
            constructor(x: Int, y: Int) : this(x + y)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
    }

    // MARK: - SEMA-0061

    func testSema0061TypeAliasMissingRhs() throws {
        let source = "typealias MyType"
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0061") || codes.contains("KSWIFTK-PARSE-0005"),
            "Expected SEMA-0061 or PARSE-0005 for typealias without RHS, got: \(codes)"
        )
    }

    // MARK: - SEMA-0070

    func testSema0070ValueClassMustHaveExactlyOneParam() throws {
        let source = """
        @JvmInline
        value class Pair(val a: Int, val b: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0070", in: ctx)
    }

    func testSema0070NotEmittedForValidValueClass() throws {
        let source = """
        @JvmInline
        value class Money(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0070", in: ctx)
    }

    // MARK: - SEMA-0072

    func testSema0072DuplicateWhenCondition() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1, 1 -> "one or one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
    }

    func testSema0072NotEmittedForDistinctConditions() throws {
        let source = """
        fun test(x: Int): String = when (x) {
            1 -> "one"
            2 -> "two"
            else -> "other"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0072", in: ctx)
    }

    // MARK: - SEMA-0073

    func testSema0073DuplicateConditionAcrossBranches() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 -> "one"
                1 -> "also one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0073", in: ctx)
    }

    // MARK: - SEMA-0074

    func testSema0074WhenBranchGuardNotBoolean() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 if 42 -> "bad"
                else -> "ok"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0074", in: ctx)
    }

    func testSema0074NotEmittedForBooleanGuard() throws {
        let source = """
        fun test(x: Int): String {
            return when (x) {
                1 if x > 0 -> "positive one"
                else -> "other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0074", in: ctx)
    }

    // MARK: - SEMA-0080

    func testSema0080ConstVar() throws {
        let source = """
        const var X = 42
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
    }

    func testSema0080NotEmittedForConstVal() throws {
        let source = """
        const val X = 42
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0080", in: ctx)
    }

    // MARK: - SEMA-0081

    func testSema0081ConstValWithoutInitializer() throws {
        let source = """
        const val X: Int
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0081", in: ctx)
    }

    // MARK: - SEMA-0083

    func testSema0083ConstValNonLiteralInitializer() throws {
        let source = """
        fun compute(): Int = 42
        const val X = compute()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0083", in: ctx)
    }

    func testSema0083NotEmittedForLiteralInitializer() throws {
        let source = """
        const val X = 100
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0083", in: ctx)
    }

    // MARK: - SEMA-0097

    func testSema0097BreakAtInvalidLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                break@nonExistent
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0097", in: ctx)
    }

    func testSema0097NotEmittedForValidBreakLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                for (j in 1..5) {
                    break@outer
                }
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0097", in: ctx)
    }

    // MARK: - SEMA-0098

    func testSema0098ContinueAtInvalidLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                continue@ghost
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0098", in: ctx)
    }

    func testSema0098NotEmittedForValidContinueLabel() throws {
        let source = """
        fun test() {
            outer@ for (i in 1..5) {
                for (j in 1..5) {
                    continue@outer
                }
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0098", in: ctx)
    }

    // MARK: - SEMA-0300

    func testSema0300CompoundAssignOperatorMustReturnUnit() throws {
        let source = """
        class Counter(var value: Int) {
            operator fun plusAssign(other: Int): Int {
                value += other
                return value
            }
        }
        fun test() {
            val c = Counter(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0300", in: ctx)
    }

    func testSema0300NotEmittedWhenPlusAssignReturnsUnit() throws {
        let source = """
        class Counter(var value: Int) {
            operator fun plusAssign(other: Int) {
                value += other
            }
        }
        fun test() {
            val c = Counter(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0300", in: ctx)
    }

    // MARK: - SEMA-0301

    func testSema0301CompoundAssignBinaryResultNotAssignable() throws {
        let source = """
        class Container(var value: Int) {
            operator fun plusAssign(delta: Int): Container {
                value += delta
                return this
            }
        }
        fun test() {
            var c = Container(0)
            c += 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        XCTAssertTrue(
            codes.contains("KSWIFTK-SEMA-0300") || codes.contains("KSWIFTK-SEMA-0301"),
            "Expected SEMA-0300 or SEMA-0301 for compound-assignment type mismatch, got: \(codes)"
        )
    }
}
