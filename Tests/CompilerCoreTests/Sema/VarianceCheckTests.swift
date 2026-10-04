@testable import CompilerCore
import Testing

@Suite
struct VarianceCheckTests {
    @Test
    func unsafeVarianceAnnotationAllowsContravariantUseInCovariantType() throws {
        let source = """
        package sample

        class Box<out T> {
            fun accept(value: @UnsafeVariance T): T = value
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            assertNoDiagnostic("KSWIFTK-SEMA-VARIANCE", in: ctx)
        }
    }
}
