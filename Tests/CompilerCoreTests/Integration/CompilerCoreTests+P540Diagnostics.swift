#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {

    @Test func testP540Sema() throws {
        let sources: [String] = [
            // testUnresolvedIdentifierInBlockEmitsDiagnostic
            """
            package sample0
                    fun test(): Int {
                        val x = missingIdent
                        return 0
                    }

            """,

            // testUnresolvedIdentifierInBinaryExprEmitsDiagnostic
            """
            package sample1
                    fun test(): Int = 1 + noSuchVar

            """,

            // testUnresolvedFunctionCallWithMultipleArgsEmitsDiagnostic
            """
            package sample2
                    fun test() = missingFun(1, 2, 3)

            """,

            // testUnresolvedFunctionCallInNestedExprEmitsDiagnostic
            """
            package sample3
                    fun known(x: Int): Int = x
                    fun test(): Int = known(unknownFn())

            """,

            // testUnresolvedMemberCallEmitsDiagnostic
            """
            package sample4
                    class Foo
                    fun test(f: Foo) = f.missing()

            """,

            // testUnresolvedSafeMemberCallEmitsDiagnostic
            """
            package sample5
                    class Foo
                    fun test(f: Foo?) = f?.missing()

            """,

            // testUnresolvedBinaryOperatorEmitsDiagnostic
            """
            package sample6
                    class Foo
                    fun test(f: Foo): Foo = f + f

            """,

            // testUnresolvedTypeAnnotationOnLocalVarEmitsDiagnostic
            """
            package sample7
                    fun test() {
                        val x: NoSuchType = 42
                    }

            """,

            // testUnresolvedReturnTypeAnnotationEmitsDiagnostic
            """
            package sample8
                    fun test(): MissingReturn = 1

            """,

            // testUnresolvedPropertyTypeAnnotationEmitsDiagnostic
            """
            package sample9
                    class Holder {
                        val x: GhostType = 0
                    }

            """,

            // testResolvedIdentifierDoesNotEmitUnresolvedDiagnostic
            """
            package sample10
                    fun test(): Int {
                        val x = 10
                        return x
                    }

            """,

            // testResolvedFunctionCallDoesNotEmitUnresolvedDiagnostic
            """
            package sample11
                    fun helper(x: Int): Int = x
                    fun test(): Int = helper(42)

            """,

            // testResolvedTypeAnnotationDoesNotEmitUnresolvedDiagnostic
            """
            package sample12
                    fun test(x: Int): String = "ok"

            """,

            // testUnresolvedLocalFunParamTypeEmitsDiagnostic
            """
            package sample13
                    fun outer() {
                        fun inner(p: Phantom): Int = 0
                    }

            """,

            // testUnresolvedLocalFunReturnTypeEmitsDiagnostic
            """
            package sample14
                    fun outer() {
                        fun inner(): Ghost = 0
                    }

            """,

            // testCascadingBinaryAddOnUnresolvedIdentifierEmitsOnlyOneError
            """
            package sample15
                    fun test(): Int = noSuchVar + 1

            """,

            // testCascadingMemberCallOnUnresolvedReceiverEmitsOnlyOneError
            """
            package sample16
                    fun test(): Int = unknownObj.method()

            """,

            // testCascadingSafeMemberCallOnUnresolvedReceiverEmitsOnlyOneError
            """
            package sample17
                    fun test() = missingVar?.call()

            """,

            // testCascadingBinarySubtractOnUnresolvedIdentifierEmitsOnlyOneError
            """
            package sample18
                    fun test(): Int = noSuchVar - 1

            """,

            // testCascadingBinaryMultiplyOnUnresolvedIdentifierEmitsOnlyOneError
            """
            package sample19
                    fun test(): Int = noSuchVar * 2

            """,

            // testResolvedMemberCallDoesNotEmitUnresolvedDiagnostic
            """
            package sample20
                    class Foo {
                        fun bar(): Int = 42
                    }
                    fun test(f: Foo): Int = f.bar()

            """,

            // testResolvedSafeMemberCallDoesNotEmitUnresolvedDiagnostic
            """
            package sample21
                    class Foo {
                        fun bar(): Int = 42
                    }
                    fun test(f: Foo?): Int? = f?.bar()

            """,

            // testResolvedBinaryAddDoesNotEmitOperatorDiagnostic
            """
            package sample22
                    fun test(): Int = 1 + 2

            """,

            // testResolvedBinaryComparisonDoesNotEmitOperatorDiagnostic
            """
            package sample23
                    fun test(): Boolean = 1 == 2

            """,

            // testResolvedStringConcatDoesNotEmitOperatorDiagnostic
            """
            package sample24
                    fun test(): String = "a" + "b"

            """,

            // testUnresolvedPropertyReadEmitsDiagnostic
            """
            package sample25
                    class Foo
                    fun test(f: Foo): Int = f.missingProp

            """,

            // testResolvedPropertyReadDoesNotEmitDiagnostic
            """
            package sample26
                    class Foo(val x: Int)
                    fun test(f: Foo): Int = f.x

            """,

            // testUnresolvedConstructorCallEmitsDiagnostic
            """
            package sample27
                    fun test() {
                        val x = NoSuchClass()
                    }

            """,

            // testResolvedConstructorCallDoesNotEmitUnresolvedDiagnostic
            """
            package sample28
                    class Point(val x: Int, val y: Int)
                    fun test(): Point = Point(1, 2)

            """,

            // testCascadingFromUnresolvedTypeAnnotationDoesNotDoubleReport
            """
            package sample29
                    fun test() {
                        val x: Ghost = 0
                        val y = x + 1
                    }

            """,

            // testMultipleUnresolvedIdentifiersEachEmitDiagnostic
            """
            package sample30
                    fun test() {
                        val a = missingA
                        val b = missingB
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testUnresolvedIdentifierInBlockEmitsDiagnostic

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)

            }
            // testUnresolvedIdentifierInBinaryExprEmitsDiagnostic

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)

            }
            // testUnresolvedFunctionCallWithMultipleArgsEmitsDiagnostic

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testUnresolvedFunctionCallInNestedExprEmitsDiagnostic

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testUnresolvedMemberCallEmitsDiagnostic

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testUnresolvedSafeMemberCallEmitsDiagnostic

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testUnresolvedBinaryOperatorEmitsDiagnostic

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testUnresolvedTypeAnnotationOnLocalVarEmitsDiagnostic

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testUnresolvedReturnTypeAnnotationEmitsDiagnostic

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testUnresolvedPropertyTypeAnnotationEmitsDiagnostic

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testResolvedIdentifierDoesNotEmitUnresolvedDiagnostic

            do {
                let sample10Path = paths[10]
                let sampleDiags = diagnosticsForPath(sample10Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testResolvedFunctionCallDoesNotEmitUnresolvedDiagnostic

            do {
                let sample11Path = paths[11]
                let sampleDiags = diagnosticsForPath(sample11Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testResolvedTypeAnnotationDoesNotEmitUnresolvedDiagnostic

            do {
                let sample12Path = paths[12]
                let sampleDiags = diagnosticsForPath(sample12Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testUnresolvedLocalFunParamTypeEmitsDiagnostic

            do {
                let sample13Path = paths[13]
                let sampleDiags = diagnosticsForPath(sample13Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testUnresolvedLocalFunReturnTypeEmitsDiagnostic

            do {
                let sample14Path = paths[14]
                let sampleDiags = diagnosticsForPath(sample14Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testCascadingBinaryAddOnUnresolvedIdentifierEmitsOnlyOneError

            do {
                let sample15Path = paths[15]
                let sampleDiags = diagnosticsForPath(sample15Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: sampleDiags)

            }
            // testCascadingMemberCallOnUnresolvedReceiverEmitsOnlyOneError

            do {
                let sample16Path = paths[16]
                let sampleDiags = diagnosticsForPath(sample16Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: sampleDiags)

            }
            // testCascadingSafeMemberCallOnUnresolvedReceiverEmitsOnlyOneError

            do {
                let sample17Path = paths[17]
                let sampleDiags = diagnosticsForPath(sample17Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0024", expected: 0, in: sampleDiags)

            }
            // testCascadingBinarySubtractOnUnresolvedIdentifierEmitsOnlyOneError

            do {
                let sample18Path = paths[18]
                let sampleDiags = diagnosticsForPath(sample18Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: sampleDiags)

            }
            // testCascadingBinaryMultiplyOnUnresolvedIdentifierEmitsOnlyOneError

            do {
                let sample19Path = paths[19]
                let sampleDiags = diagnosticsForPath(sample19Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 1, in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 0, in: sampleDiags)

            }
            // testResolvedMemberCallDoesNotEmitUnresolvedDiagnostic

            do {
                let sample20Path = paths[20]
                let sampleDiags = diagnosticsForPath(sample20Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testResolvedSafeMemberCallDoesNotEmitUnresolvedDiagnostic

            do {
                let sample21Path = paths[21]
                let sampleDiags = diagnosticsForPath(sample21Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testResolvedBinaryAddDoesNotEmitOperatorDiagnostic

            do {
                let sample22Path = paths[22]
                let sampleDiags = diagnosticsForPath(sample22Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testResolvedBinaryComparisonDoesNotEmitOperatorDiagnostic

            do {
                let sample23Path = paths[23]
                let sampleDiags = diagnosticsForPath(sample23Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testResolvedStringConcatDoesNotEmitOperatorDiagnostic

            do {
                let sample24Path = paths[24]
                let sampleDiags = diagnosticsForPath(sample24Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testUnresolvedPropertyReadEmitsDiagnostic

            do {
                let sample25Path = paths[25]
                let sampleDiags = diagnosticsForPath(sample25Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testResolvedPropertyReadDoesNotEmitDiagnostic

            do {
                let sample26Path = paths[26]
                let sampleDiags = diagnosticsForPath(sample26Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testUnresolvedConstructorCallEmitsDiagnostic

            do {
                let sample27Path = paths[27]
                let sampleDiags = diagnosticsForPath(sample27Path, in: ctx)


                        #expect(
                            sampleDiags.contains(where: { ["KSWIFTK-SEMA-0022", "KSWIFTK-SEMA-0023"].contains($0.code) }),
                            "Expected unresolved-reference diagnostic for unknown constructor, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testResolvedConstructorCallDoesNotEmitUnresolvedDiagnostic

            do {
                let sample28Path = paths[28]
                let sampleDiags = diagnosticsForPath(sample28Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testCascadingFromUnresolvedTypeAnnotationDoesNotDoubleReport

            do {
                let sample29Path = paths[29]
                let sampleDiags = diagnosticsForPath(sample29Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)
                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 0, in: sampleDiags)

            }
            // testMultipleUnresolvedIdentifiersEachEmitDiagnostic

            do {
                let sample30Path = paths[30]
                let sampleDiags = diagnosticsForPath(sample30Path, in: ctx)


                        assertDiagnosticCount("KSWIFTK-SEMA-0022", expected: 2, in: sampleDiags)

            }

        }
    }

}
#endif
