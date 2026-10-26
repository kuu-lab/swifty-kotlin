@testable import CompilerCore
import Testing

@Suite
struct UnresolvedAnnotationTests {
    @Test
    func unresolvedDeclarationAnnotationIsReported() throws {
        let ctx = makeContextFromSource(
            """
            @NonExistent
            fun f() = 1

            fun main() { println(f()) }
            """,
            allowDefaultStdlibLibrary: true
        )
        try runSema(ctx)

        let unresolvedAnnotations = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0022" && $0.message == "Unresolved reference 'NonExistent'."
        }
        #expect(unresolvedAnnotations.count == 1, "Expected one unresolved annotation diagnostic, got: \(unresolvedAnnotations)")
    }
}
