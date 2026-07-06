#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - CLASS-001: End-to-end companion object (factory, const val, singleton)

extension CompanionObjectTests {
    /// Verify `Foo.create()` companion factory resolves through sema with no errors.
    @Test func testCompanionFactoryFunctionResolvesEndToEnd() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for Foo.create(), got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify `Foo.MAX_COUNT` const val access resolves through sema with no errors.
    @Test func testCompanionConstValAccessResolvesEndToEnd() throws {
        let source = """
        package test
        class Foo {
            companion object {
                const val MAX_COUNT: Int = 100
            }
        }
        fun main() {
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors for Foo.MAX_COUNT, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Combined: factory function + const val in the same companion, used from main.
    @Test func testCompanionFactoryAndConstValCombinedEndToEnd() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                const val MAX_COUNT: Int = 100
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no sema errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Verify companion factory + const val lowers to KIR with companion init synthesized.
    @Test func testCompanionFactoryAndConstValKIRLowering() throws {
        let source = """
        package test
        class Foo(val x: Int) {
            companion object {
                const val MAX_COUNT: Int = 100
                fun create(): Foo = Foo(0)
            }
        }
        fun main() {
            val f: Foo = Foo.create()
            val m: Int = Foo.MAX_COUNT
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }

        // Companion initializer must be synthesized
        #expect(
            functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
            "Expected synthesized companion initializer, got: \(functionNames)"
        )

        // The create function must be lowered
        #expect(
            functionNames.contains("create"),
            "Expected companion function 'create' in KIR, got: \(functionNames)"
        )
    }

    /// Verify exactly one companion singleton init function is synthesized.
    @Test func testCompanionSingletonInitSynthesizedExactlyOnce() throws {
        let source = """
        class Host {
            companion object {
                val counter: Int = 1
                fun get(): Int = counter
            }
        }
        fun main() {
            val v: Int = Host.get()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let expectedInitName = try companionInitializerName(forOwnerNamed: "Host", in: ctx)
        let companionInits = findAllKIRFunctions(in: module).compactMap { function -> String? in
            let name = ctx.interner.resolve(function.name)
            return name == expectedInitName ? name : nil
        }
        #expect(
            companionInits.count == 1,
            "Expected exactly one Host companion initializer, got \(companionInits.count): \(companionInits)"
        )
    }

    /// Named companion object should resolve factory calls via `ClassName.factoryFn()`.
    @Test func testNamedCompanionFactoryResolvesEndToEnd() throws {
        let source = """
        package test
        class Widget {
            companion object Factory {
                fun create(): Widget = Widget()
            }
        }
        fun main() {
            val w: Widget = Widget.create()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no errors for named companion factory, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Companion lowering through the full pipeline including LoweringPhase.
    @Test func testCompanionObjectFullPipelineLowering() throws {
        let source = """
        class Foo(val x: Int) {
            companion object {
                const val DEFAULT: Int = 42
                fun of(v: Int): Foo = Foo(v)
            }
        }
        fun main() {
            val d: Int = Foo.DEFAULT
            val f: Foo = Foo.of(1)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        #expect(
            !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
            "Expected no errors after full lowering, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

    /// Companion object with property initializer generates correct KIR body.
    @Test func testCompanionPropertyInitializerInKIRBody() throws {
        let source = """
        class Config {
            companion object {
                val defaultTimeout: Int = 30
            }
        }
        fun main(): Int = Config.defaultTimeout
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )

            let module = try #require(ctx.kir)
            // Find the companion init function and verify it has a copy instruction
            // (property initialization writes the initial value)
            let expectedInitName = try companionInitializerName(forOwnerNamed: "Config", in: ctx)
            let companionInitFn = findAllKIRFunctions(in: module).compactMap { function -> KIRFunction? in
                let name = ctx.interner.resolve(function.name)
                return name == expectedInitName ? function : nil
            }.first
            let initBody = try #require(companionInitFn, "Expected companion init function").body
            let hasCopy = initBody.contains { instruction in
                if case .copy = instruction { return true }
                return false
            }
            #expect(hasCopy, "Expected copy instruction in companion init body for property initialization")
        }
    }

    private func companionInitializerName(
        forOwnerNamed ownerName: String,
        in ctx: CompilationContext
    ) throws -> String {
        let sema = try #require(ctx.sema)
        let ownerSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(ownerName)]))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: ownerSymbol))
        return "__companion_init_\(ownerSymbol.rawValue)_\(companionSymbol.rawValue)"
    }
}
#endif
