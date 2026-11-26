#if canImport(Testing)
import Testing
@testable import CompilerTestSupport

@Suite
struct SecondaryConstructorDeprecationSuppressionTests {
    @Test
    func suppressDeprecationOnSecondaryConstructorCoversDeprecatedParameterType() throws {
        let ctx = try semaContext(from: """
        @Deprecated("x") interface Old

        class C(val a: Int) {
            @Suppress("UNUSED_PARAMETER", "DEPRECATION")
            @Deprecated("y")
            constructor(a: Int, b: Old) : this(a)
        }

        class D(val a: Int) {
            constructor(a: Int, b: Old) : this(a)
        }

        class Outer {
            class N(val a: Int) {
                @Suppress("DEPRECATION")
                constructor(a: Int, b: Old) : this(a)
            }
        }
        """, includeStdlib: false)
        let lines = ctx.diagnosticsWithCode("KSWIFTK-SEMA-DEPRECATED", severity: .warning)
            .compactMap { $0.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line } }
        #expect(lines == [10])
    }
}
#endif
