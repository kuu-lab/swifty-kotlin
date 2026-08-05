#if canImport(Testing)
import Testing
@testable import CompilerCore

@Suite struct OpenFinalOverrideGenericReturnTests {

    @Test func testOpenFinalOverrideGenericReturnSema() throws {
        let sources: [String] = [
            // testWidenedGenericListOverrideIsRejected
            """
            package sample0
                    open class ListProvider<T> {
                        open fun items(): List<T> = emptyList()
                    }
                    class Widened : ListProvider<String>() {
                        override fun items(): List<Any> = emptyList()
                    }

            """,

            // testCovariantGenericListOverrideIsAccepted
            """
            package sample1
                    open class ListProvider<T> {
                        open fun items(): List<T> = emptyList()
                    }
                    class Narrowed : ListProvider<Number>() {
                        override fun items(): List<Int> = emptyList()
                    }

            """,

            // testWidenedTypeParameterReturnOverrideIsRejected
            """
            package sample2
                    open class ValueHolder<T> {
                        open fun value(): T = throw RuntimeException()
                    }
                    class Widened : ValueHolder<String>() {
                        override fun value(): Any = "x"
                    }

            """,

            // testGenericInterfaceOverrideWithSameTypeParameterIsAccepted
            """
            package sample3
                    interface Seq<out T> {
                        operator fun iterator(): Iterator<T>
                    }
                    class MySeq<T>(val it: Iterator<T>) : Seq<T> {
                        override fun iterator(): Iterator<T> = it
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testWidenedGenericListOverrideIsRejected

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)

                        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: sampleDiags)

            }
            // testCovariantGenericListOverrideIsAccepted

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)

                        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testWidenedTypeParameterReturnOverrideIsRejected

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)

                        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: sampleDiags)

            }
            // testGenericInterfaceOverrideWithSameTypeParameterIsAccepted

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)

                        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }

        }
    }

}
#endif
