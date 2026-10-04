#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CompilerCoreTests {

    @Test func testCCSema() throws {
        let sources: [String] = [
            // testSemaBindsSimpleCallExpression
            """
            package sample0
                    fun foo(a: Int) = a
                    fun bar() = foo(1)

            """,

            // testWhenExhaustivenessDiagnosticForBooleanWithoutElse
            """
            package sample1
                    fun test() {
                        when (true) {
                            true -> 1
                        }
                    }

            """,

            // testWhenExhaustivenessDiagnosticForNullableBooleanWithoutNullBranch
            """
            package sample2
                    fun test(x: Boolean?) {
                        when (x) {
                            true -> 1
                            false -> 0
                        }
                    }

            """,

            // testWhenExhaustivenessAcceptsNullableBooleanWithNullBranch
            """
            package sample3
                    fun test(x: Boolean?) {
                        when (x) {
                            true -> 1
                            false -> 0
                            null -> 2
                        }
                    }

            """,

            // testWhenExhaustivenessAcceptsEnumWithAllEntries
            """
            package sample4
                    enum class Color { Red, Green }
                    fun pick(color: Color) = when (color) {
                        Red -> 1
                        Green -> 2
                    }

            """,

            // testWhenExhaustivenessAcceptsEnumWithGroupedBranches
            """
            package sample5
                    enum class Color { Red, Green, Blue }
                    fun pick(color: Color) = when (color) {
                        Red, Green -> 1
                        Blue -> 2
                    }

            """,

            // testWhenExhaustivenessAcceptsEnumWithQualifiedGroupedBranches
            """
            package sample6
                    enum class Color { Red, Green, Blue }
                    fun pick(color: Color) = when (color) {
                        Color.Red, Color.Green -> 1
                        Color.Blue -> 2
                    }

            """,

            // testWhenExhaustivenessAcceptsSealedWithAllDirectSubtypes
            """
            package sample7
                    sealed class Expr
                    object A : Expr()
                    object B : Expr()
                    fun eval(e: Expr): Int {
                        when (e) {
                            A -> 1
                            B -> 2
                        }
                    }

            """,

            // testWhenQualifiedGroupedObjectBranchesResolveWithoutUnresolvedMemberErrors
            """
            package sample8
                    sealed class Expr {
                        object A : Expr()
                        object B : Expr()
                    }
                    fun eval(e: Expr): Int = when (e) {
                        Expr.A, Expr.B -> 1
                        else -> 0
                    }

            """,

            // testWhenQualifiedGroupedObjectBranchesWithoutElseReportNonExhaustive
            """
            package sample9
                    sealed class Expr {
                        object A : Expr()
                        object B : Expr()
                    }
                    fun eval(e: Expr): Int = when (e) {
                        Expr.A -> 1
                    }

            """,

            // testSealedInterfaceWhenGroupedIsBranchesAreExhaustive
            """
            package sample10
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

            """,

            // testSealedInterfaceWhenGroupedIsBranchesReportMissingSubtype
            """
            package sample11
                    sealed interface Expr
                    class Literal : Expr
                    class Add : Expr
                    class Multiply : Expr

                    fun eval(e: Expr): String {
                        when (e) {
                            is Literal, is Add -> "few"
                        }
                    }

            """,

            // testWhenExhaustivenessDiagnosticForSealedMissingSubtype
            """
            package sample12
                    sealed class Expr
                    object A : Expr()
                    object B : Expr()
                    fun eval(e: Expr): Int {
                        when (e) {
                            A -> 1
                        }
                    }

            """,

            // testSealedInterfaceWhenExhaustivenessAcceptsAllBranches
            """
            package sample13
                    sealed interface Expr
                    class Literal : Expr
                    class Add : Expr

                    fun eval(e: Expr): String {
                        when (e) {
                            is Literal -> "lit"
                            is Add -> "add"
                        }
                    }

            """,

            // testWhenNullBranchSmartCastsLocalToNonNullInOtherBranches
            """
            package sample14
                    fun takesInt(x: Int) = x
                    fun smart(x: Int?): Int {
                        when (x) {
                            null -> 0
                            else -> takesInt(x)
                        }
                    }

            """,

            // testWhenBranchSmartCastsSealedSubjectToMatchedSubtype
            """
            package sample15
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

            """,

            // testWhenBooleanBranchSmartCastsNullableBooleanToNonNull
            """
            package sample16
                    fun takesBool(x: Boolean) = x
                    fun eval(b: Boolean?) {
                        when (b) {
                            true -> takesBool(b)
                            false -> takesBool(b)
                            null -> false
                        }
                    }

            """,

            // testTypeCheckReportsReturnTypeMismatchForExpressionBody
            """
            package sample17
                    fun bad(): Int = "x"

            """,

            // testPropertyInitializerInfersTypeForSubsequentCalls
            """
            package sample18
                    val num = 1
                    fun takesInt(x: Int) = x
                    fun use() = takesInt(num)

            """,

            // testPropertyInitializerTypeMismatchReportsTypeDiagnostic
            """
            package sample19
                    val bad: Int = "x"

            """,

            // testParameterDefaultValueTypeMismatchReportsTypeDiagnostic
            """
            package sample20
                    fun bad(x: Int = "x"): Int = x

            """,

            // testPrimaryConstructorParameterDefaultValueTypeMismatchReportsTypeDiagnostic
            """
            package sample21
                    class Bad(val x: Int = "x")

            """,

            // testPropertyGetterTypeMismatchReportsTypeDiagnostic
            """
            package sample22
                    val bad: Int {
                        get() = "x"
                    }

            """,

            // testSetterOnValReportsDiagnostic
            """
            package sample23
                    val bad: Int {
                        set(value) {
                            value
                        }
                    }

            """,

            // testClassInitBlockIsTypeChecked
            """
            package sample24
                    fun takesInt(x: Int) = x
                    class C {
                        init {
                            takesInt("x")
                        }
                    }

            """,

            // testOverloadRejectsBooleanArgumentForIntParameter
            """
            package sample25
                    fun foo(a: Int) = a
                    fun bar() = foo(true)

            """,

            // testCallSupportsMixedNamedAndPositionalArguments
            """
            package sample26
                    fun pick(x: Int, flag: Boolean) = x
                    fun use() = pick(1, flag = true)

            """,

            // testCallRejectsPositionalArgumentAfterNamedArgument
            """
            package sample27
                    fun pick(x: Int, y: Int) = x
                    fun use() = pick(y = 1, 2)

            """,

            // testCallSupportsNonTrailingVarargWithNamedTail
            """
            package sample28
                    fun sum(vararg items: Int, tail: Int) = tail
                    fun use() = sum(1, 2, tail = 3)

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testSemaBindsSimpleCallExpression

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        let sema = try #require(ctx.sema)
                        #expect(!(sema.bindings.callBindings.isEmpty))

            }
            // testWhenExhaustivenessDiagnosticForBooleanWithoutElse

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)

            }
            // testWhenExhaustivenessDiagnosticForNullableBooleanWithoutNullBranch

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)

            }
            // testWhenExhaustivenessAcceptsNullableBooleanWithNullBranch

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)

            }
            // testWhenExhaustivenessAcceptsEnumWithAllEntries

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)

            }
            // testWhenExhaustivenessAcceptsEnumWithGroupedBranches

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)

            }
            // testWhenExhaustivenessAcceptsEnumWithQualifiedGroupedBranches

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testWhenExhaustivenessAcceptsSealedWithAllDirectSubtypes

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: sampleDiags)

            }
            // testWhenQualifiedGroupedObjectBranchesResolveWithoutUnresolvedMemberErrors

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testWhenQualifiedGroupedObjectBranchesWithoutElseReportNonExhaustive

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testSealedInterfaceWhenGroupedIsBranchesAreExhaustive

            do {
                let sample10Path = paths[10]
                let sampleDiags = diagnosticsForPath(sample10Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: sampleDiags)

            }
            // testSealedInterfaceWhenGroupedIsBranchesReportMissingSubtype

            do {
                let sample11Path = paths[11]
                let sampleDiags = diagnosticsForPath(sample11Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: sampleDiags)
                        let sealedDiag = sampleDiags.first { $0.code == "KSWIFTK-SEMA-0071" }
                        #expect(sealedDiag != nil)
                        #expect(
                            sealedDiag?.message.contains("Multiply") == true,
                            "Expected diagnostic message to mention missing subtype 'Multiply'"
                        )

            }
            // testWhenExhaustivenessDiagnosticForSealedMissingSubtype

            do {
                let sample12Path = paths[12]
                let sampleDiags = diagnosticsForPath(sample12Path, in: ctx)


                        // P5-78: sealed missing-branch diagnostic now uses KSWIFTK-SEMA-0071
                        assertHasDiagnostic("KSWIFTK-SEMA-0071", in: sampleDiags)

                        // Also assert that the diagnostic text mentions missing branches and the missing subtype.
                        let sealedDiag = sampleDiags.first { $0.code == "KSWIFTK-SEMA-0071" }
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
            // testSealedInterfaceWhenExhaustivenessAcceptsAllBranches

            do {
                let sample13Path = paths[13]
                let sampleDiags = diagnosticsForPath(sample13Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0004", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0071", in: sampleDiags)

            }
            // testWhenNullBranchSmartCastsLocalToNonNullInOtherBranches

            do {
                let sample14Path = paths[14]
                let sampleDiags = diagnosticsForPath(sample14Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testWhenBranchSmartCastsSealedSubjectToMatchedSubtype

            do {
                let sample15Path = paths[15]
                let sampleDiags = diagnosticsForPath(sample15Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testWhenBooleanBranchSmartCastsNullableBooleanToNonNull

            do {
                let sample16Path = paths[16]
                let sampleDiags = diagnosticsForPath(sample16Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testTypeCheckReportsReturnTypeMismatchForExpressionBody

            do {
                let sample17Path = paths[17]
                let sampleDiags = diagnosticsForPath(sample17Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testPropertyInitializerInfersTypeForSubsequentCalls

            do {
                let sample18Path = paths[18]
                let sampleDiags = diagnosticsForPath(sample18Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testPropertyInitializerTypeMismatchReportsTypeDiagnostic

            do {
                let sample19Path = paths[19]
                let sampleDiags = diagnosticsForPath(sample19Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testParameterDefaultValueTypeMismatchReportsTypeDiagnostic

            do {
                let sample20Path = paths[20]
                let sampleDiags = diagnosticsForPath(sample20Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testPrimaryConstructorParameterDefaultValueTypeMismatchReportsTypeDiagnostic

            do {
                let sample21Path = paths[21]
                let sampleDiags = diagnosticsForPath(sample21Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testPropertyGetterTypeMismatchReportsTypeDiagnostic

            do {
                let sample22Path = paths[22]
                let sampleDiags = diagnosticsForPath(sample22Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testSetterOnValReportsDiagnostic

            do {
                let sample23Path = paths[23]
                let sampleDiags = diagnosticsForPath(sample23Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0005", in: sampleDiags)

            }
            // testClassInitBlockIsTypeChecked

            do {
                let sample24Path = paths[24]
                let sampleDiags = diagnosticsForPath(sample24Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testOverloadRejectsBooleanArgumentForIntParameter

            do {
                let sample25Path = paths[25]
                let sampleDiags = diagnosticsForPath(sample25Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testCallSupportsMixedNamedAndPositionalArguments

            do {
                let sample26Path = paths[26]
                let sampleDiags = diagnosticsForPath(sample26Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testCallRejectsPositionalArgumentAfterNamedArgument

            do {
                let sample27Path = paths[27]
                let sampleDiags = diagnosticsForPath(sample27Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testCallSupportsNonTrailingVarargWithNamedTail

            do {
                let sample28Path = paths[28]
                let sampleDiags = diagnosticsForPath(sample28Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }

        }
    }

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

}
#endif
