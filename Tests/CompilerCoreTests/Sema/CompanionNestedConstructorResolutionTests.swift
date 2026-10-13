#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompanionNestedConstructorResolutionTests {
    @Test func companionCallIncludesNestedGenericConstructorAlongsideFactory() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                fun Choice(f: (String) -> Int): Int = 1
                fun make(xs: List<Int>, f: (String) -> Int): Choice<Int> = Choice(xs, f)
            }
            class Choice<T>(val xs: List<T>, val f: (String) -> Int, val marker: Int = 0)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        let classSymbol = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("A"),
            ctx.interner.intern("Choice"),
        ]))

        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == classSymbol)
        #expect(sema.bindings.exprType(for: call) == sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        ))))
    }

    @Test func localCallableShadowsSameNamedNestedConstructor() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                fun make(xs: List<Int>, f: (String) -> Int): String {
                    fun Choice(xs: List<Int>, f: (String) -> Int): String = "local"
                    return Choice(xs, f)
                }
            }
            class Choice<T>(val xs: List<T>, val f: (String) -> Int)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))

        #expect(chosen.kind == .function)
        #expect(chosen.flags.contains(.localFunction))
    }

    @Test func inaccessibleNestedConstructorYieldsToApplicableCompanionFunction() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                fun Choice(value: Number): String = "factory"
                fun make(): String = Choice(1)
            }
            class Choice private constructor(val value: Int)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        #expect(chosen.kind == .function)
    }

    @Test func abstractNestedClassDoesNotHideApplicableCompanionFunction() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                fun Choice(value: Number): String = "factory"
                fun make(): String = Choice(1)
            }
            abstract class Choice(val value: Int)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" }, "Unexpected diagnostics: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        #expect(chosen.kind == .function)
    }

    @Test func hiddenDeprecatedFactoryDoesNotSuppressMatchingConstructor() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                @Deprecated("hidden compatibility factory", level = DeprecationLevel.HIDDEN)
                fun Choice(xs: List<Int>, f: (String) -> Int, marker: Int = 0): Choice? = null
                fun make(xs: List<Int>, f: (String) -> Int): Choice = Choice(xs, f)
            }
            class Choice(val xs: List<Int>, val f: (String) -> Int, val marker: Int = 0)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-DEPRECATED" })

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
    }

    @Test func typeAliasStillResolvesItsUnderlyingConstructor() throws {
        let ctx = makeContextFromSource("""
        package sample
        class Box(val value: Int)
        typealias Alias = Box
        fun make(): Box = Alias(1)
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Alias", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
    }

    @Test func applicableCompanionFunctionRemainsAConstructorCompetingCandidate() throws {
        let ctx = makeContextFromSource("""
        class A {
            companion object {
                fun Choice(value: String): String = value
                fun make(): String = Choice("factory")
            }
            class Choice(val value: Int)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Choice", in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosen = try #require(sema.symbols.symbol(binding.chosenCallee))
        #expect(chosen.kind == .function)
    }

    @Test func ambiguousCompanionOverloadsRemainAmbiguousWithNestedConstructor() throws {
        let ctx = makeContextFromSource("""
        interface Left
        interface Right
        class Both : Left, Right
        class A {
            companion object {
                fun Choice(value: Left): String = "left"
                fun Choice(value: Right): String = "right"
                fun make(value: Both) = Choice(value)
            }
            class Choice(value: Any)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1, "Expected ambiguity: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "Unexpected diagnostics: \(errors)")
    }
}
#endif
