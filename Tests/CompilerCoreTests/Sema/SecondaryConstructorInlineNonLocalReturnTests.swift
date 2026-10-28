@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SecondaryConstructorInlineNonLocalReturnTests {
    @Test
    func inlineLambdaReturnTargetsSecondaryConstructor() throws {
        let ctx = makeContextFromSource("""
        inline fun run2(block: () -> Unit) = block()

        class Box {
            val value: Int
            constructor(flag: Boolean) {
                if (flag) {
                    value = 1
                    run2 { return }
                } else {
                    value = 2
                }
            }
        }

        fun functionControl(): Int {
            run2 { return 42 }
            return -1
        }

        class ConstructorControl {
            var marker = false
            constructor() {
                run2 { return@run2 }
                marker = true
            }
        }
        """, allowDefaultStdlibLibrary: false)

        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let bindings = sema.bindings
        let constructorReturns = bindings.functionReturnLambdaPaths.keys.filter { expression in
            guard let target = bindings.identifierSymbol(for: expression),
                  sema.symbols.symbol(target)?.kind == .constructor
            else { return false }
            return true
        }
        #expect(constructorReturns.count == 1)
    }

    @Test
    func nonInlineLambdaReturnCannotTargetConstructor() throws {
        let ctx = makeContextFromSource("""
        fun runPlain(block: () -> Unit) = block()

        class Box {
            constructor() { runPlain { return } }
        }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test(arguments: ["42", "Unit"])
    func constructorRejectsReturnValues(value: String) throws {
        let ctx = makeContextFromSource("""
        inline fun run2(block: () -> Unit) = block()

        class Box {
            constructor() { run2 { return \(value) } }
        }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test
    func inlineReturnParticipatesInConstructorPropertyInitialization() throws {
        let ctx = makeContextFromSource("""
        inline fun run2(block: () -> Unit) = block()

        class Missing {
            val value: Int
            constructor() {
                run2 { return }
                value = 1
            }
        }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0424", in: ctx)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0042" })
    }
}
