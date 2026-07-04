#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite @MainActor
struct CompilerCoreTests {
    @Test func testLexerRecognizesQuestionQuestionSymbol() {
        let source = Data("a ?? b".utf8)
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let lexer = KotlinLexer(
            file: FileID(rawValue: 0),
            source: source,
            interner: interner,
            diagnostics: diagnostics
        )

        let tokens = lexer.lexAll()
        #expect(tokens.contains { token in
            token.kind == .symbol(.questionQuestion)
        })
        #expect(!(diagnostics.hasError))
    }

    @Test func testSemaBindsSimpleCallExpression() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(1)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        #expect(!(sema.bindings.callBindings.isEmpty))
    }

    @Test func testWhenExhaustivenessDiagnosticForBooleanWithoutElse() throws {
        let source = """
        fun test() {
            when (true) {
                true -> 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testWhenExhaustivenessDiagnosticForNullableBooleanWithoutNullBranch() throws {
        let source = """
        fun test(x: Boolean?) {
            when (x) {
                true -> 1
                false -> 0
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testWhenExhaustivenessAcceptsNullableBooleanWithNullBranch() throws {
        let source = """
        fun test(x: Boolean?) {
            when (x) {
                true -> 1
                false -> 0
                null -> 2
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testWhenExhaustivenessAcceptsEnumWithAllEntries() throws {
        let source = """
        enum class Color { Red, Green }
        fun pick(color: Color) = when (color) {
            Red -> 1
            Green -> 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testWhenExhaustivenessAcceptsEnumWithGroupedBranches() throws {
        let source = """
        enum class Color { Red, Green, Blue }
        fun pick(color: Color) = when (color) {
            Red, Green -> 1
            Blue -> 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
    }

    @Test func testWhenExhaustivenessAcceptsEnumWithQualifiedGroupedBranches() throws {
        let source = """
        enum class Color { Red, Green, Blue }
        fun pick(color: Color) = when (color) {
            Color.Red, Color.Green -> 1
            Color.Blue -> 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testWhenExhaustivenessAcceptsSealedWithAllDirectSubtypes() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun eval(e: Expr): Int {
            when (e) {
                A -> 1
                B -> 2
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testWhenQualifiedGroupedObjectBranchesResolveWithoutUnresolvedMemberErrors() throws {
        let source = """
        sealed class Expr {
            object A : Expr()
            object B : Expr()
        }
        fun eval(e: Expr): Int = when (e) {
            Expr.A, Expr.B -> 1
            else -> 0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testWhenQualifiedGroupedObjectBranchesWithoutElseReportNonExhaustive() throws {
        let source = """
        sealed class Expr {
            object A : Expr()
            object B : Expr()
        }
        fun eval(e: Expr): Int = when (e) {
            Expr.A -> 1
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test func testSealedInterfaceWhenGroupedIsBranchesAreExhaustive() throws {
        let source = """
        sealed interface Expr
        class Literal : Expr
        class Add : Expr
        class Multiply : Expr

        fun eval(e: Expr): String {
            when (e) {
                is Literal, is Add -> "few"
                is Multiply -> "mul"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testSealedInterfaceWhenGroupedIsBranchesReportMissingSubtype() throws {
        let source = """
        sealed interface Expr
        class Literal : Expr
        class Add : Expr
        class Multiply : Expr

        fun eval(e: Expr): String {
            when (e) {
                is Literal, is Add -> "few"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
        let sealedDiag = ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0071" }
        #expect(sealedDiag != nil)
        #expect(
            sealedDiag?.message.contains("Multiply") == true,
            "Expected diagnostic message to mention missing subtype 'Multiply'"
        )
    }

    @Test func testWhenExhaustivenessDiagnosticForSealedMissingSubtype() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun eval(e: Expr): Int {
            when (e) {
                A -> 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // P5-78: sealed missing-branch diagnostic now uses KSWIFTK-SEMA-0071
        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: ctx)

        // Also assert that the diagnostic text mentions missing branches and the missing subtype.
        let sealedDiag = ctx.diagnostics.diagnostics.first { $0.code == "KSWIFTK-SEMA-0071" }
        #expect(sealedDiag != nil)
        #expect(
            sealedDiag?.message.contains("Missing branches") == true,
            "Expected diagnostic message to mention missing branches"
        )
        #expect(
            sealedDiag?.message.contains("B") == true,
            "Expected diagnostic message to mention missing subtype 'B'"
        )
    }

    // P5-78: sealed interface when exhaustiveness accepts all branches
    @Test func testSealedInterfaceWhenExhaustivenessAcceptsAllBranches() throws {
        let source = """
        sealed interface Expr
        class Literal : Expr
        class Add : Expr

        fun eval(e: Expr): String {
            when (e) {
                is Literal -> "lit"
                is Add -> "add"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: ctx)
    }

    @Test func testWhenNullBranchSmartCastsLocalToNonNullInOtherBranches() throws {
        let source = """
        fun takesInt(x: Int) = x
        fun smart(x: Int?): Int {
            when (x) {
                null -> 0
                else -> takesInt(x)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testWhenBranchSmartCastsSealedSubjectToMatchedSubtype() throws {
        let source = """
        sealed class Expr
        object A : Expr()
        object B : Expr()
        fun takesA(x: A) = 1
        fun eval(e: Expr): Int {
            when (e) {
                A -> takesA(e)
                B -> 0
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testWhenBooleanBranchSmartCastsNullableBooleanToNonNull() throws {
        let source = """
        fun takesBool(x: Boolean) = x
        fun eval(b: Boolean?) {
            when (b) {
                true -> takesBool(b)
                false -> takesBool(b)
                null -> false
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testTypeCheckReportsReturnTypeMismatchForExpressionBody() throws {
        let source = """
        fun bad(): Int = "x"
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testPropertyInitializerInfersTypeForSubsequentCalls() throws {
        let source = """
        val num = 1
        fun takesInt(x: Int) = x
        fun use() = takesInt(num)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testPropertyInitializerTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int = "x"
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testPropertyGetterTypeMismatchReportsTypeDiagnostic() throws {
        let source = """
        val bad: Int {
            get() = "x"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test func testSetterOnValReportsDiagnostic() throws {
        let source = """
        val bad: Int {
            set(value) {
                value
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0005", in: ctx)
    }

    @Test func testClassInitBlockIsTypeChecked() throws {
        let source = """
        fun takesInt(x: Int) = x
        class C {
            init {
                takesInt("x")
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testOverloadRejectsBooleanArgumentForIntParameter() throws {
        let source = """
        fun foo(a: Int) = a
        fun bar() = foo(true)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testCallSupportsMixedNamedAndPositionalArguments() throws {
        let source = """
        fun pick(x: Int, flag: Boolean) = x
        fun use() = pick(1, flag = true)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testCallRejectsPositionalArgumentAfterNamedArgument() throws {
        let source = """
        fun pick(x: Int, y: Int) = x
        fun use() = pick(y = 1, 2)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    @Test func testCallSupportsNonTrailingVarargWithNamedTail() throws {
        let source = """
        fun sum(vararg items: Int, tail: Int) = tail
        fun use() = sum(1, 2, tail = 3)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

    // MARK: - P5-40 Regression: Strict unresolved reference / type diagnostics

    // MARK: - P5-40 Cascading diagnostic suppression

    // MARK: - P5-40 Resolved negative tests (no spurious diagnostics)
}
#endif
