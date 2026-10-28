@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KUU3521InterfaceDiamondSemaTests {
    @Test
    func subinterfaceOverrideSatisfiesDirectParentDiamond() throws {
        let source = """
        interface BK { fun foo(): String = "10" }
        interface KTrait: BK { override fun foo() = "30" }
        class A : BK, KTrait {}

        interface Base { fun bar(): String = "base" }
        interface Left: Base { override fun bar() = "left" }
        interface Right: Base { override fun bar() = "right" }
        class Diamond: Left, Right {}

        fun main() { println(A().foo()) }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diamondConflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0171"
            }
            #expect(diamondConflicts.count == 1)
            #expect(diamondConflicts.first?.message.contains("Class 'Diamond'") == true)

            let unexpectedErrors = ctx.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code != "KSWIFTK-SEMA-0171"
            }
            #expect(unexpectedErrors.isEmpty, "Unexpected diagnostics: \(unexpectedErrors)")
        }
    }
}
