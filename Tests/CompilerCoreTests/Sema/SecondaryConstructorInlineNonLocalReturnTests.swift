@testable import CompilerCore
import Testing

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

    @Test
    func constructorRejectsReturnValues() throws {
        let ctx = makeContextFromSource("""
        inline fun run2(block: () -> Unit) = block()

        class Box {
            constructor() { run2 { return 42 } }
        }
        """, allowDefaultStdlibLibrary: false)

        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0042", in: ctx)
    }

    @Test
    func constructorAcceptsReturnUnitWhenInitializingProperty() throws {
        let ctx = makeContextFromSource("""
        class A {
            val prop: Int
            constructor(arg: Boolean) {
                if (arg) { prop = 1; return Unit }
                prop = 2
            }
        }
        fun main() { println(A(true).prop) }
        """, allowDefaultStdlibLibrary: false)

        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let classFQName = [ctx.interner.intern("A")]
        let constructor = try #require(sema.symbols.children(ofFQName: classFQName).first {
            sema.symbols.symbol($0)?.kind == .constructor
        })
        let module = try #require(ctx.kir)
        let constructorFunction = try #require(findAllKIRFunctions(in: module).first { $0.symbol == constructor })
        #expect(!constructorFunction.body.contains(.returnUnit))
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
