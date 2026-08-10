#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - CLASS-001: End-to-end companion object (factory, const val, singleton)

extension CompanionObjectTests {

    @Test func testFactoryConstAndLoweringSema() throws {
        let sources: [String] = [
            // testCompanionFactoryFunctionResolvesEndToEnd
            """
            package sample0
                    class Foo(val x: Int) {
                        companion object {
                            fun create(): Foo = Foo(0)
                        }
                    }
                    fun main() {
                        val f: Foo = Foo.create()
                    }

            """,

            // testCompanionConstValAccessResolvesEndToEnd
            """
            package sample1
                    class Foo {
                        companion object {
                            const val MAX_COUNT: Int = 100
                        }
                    }
                    fun main() {
                        val m: Int = Foo.MAX_COUNT
                    }

            """,

            // testCompanionFactoryAndConstValCombinedEndToEnd
            """
            package sample2
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

            """,

            // testNamedCompanionFactoryResolvesEndToEnd
            """
            package sample3
                    class Widget {
                        companion object Factory {
                            fun create(): Widget = Widget()
                        }
                    }
                    fun main() {
                        val w: Widget = Widget.create()
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testCompanionFactoryFunctionResolvesEndToEnd

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for Foo.create(), got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionConstValAccessResolvesEndToEnd

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors for Foo.MAX_COUNT, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionFactoryAndConstValCombinedEndToEnd

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no sema errors, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNamedCompanionFactoryResolvesEndToEnd

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        #expect(
                            !(sampleDiags.contains(where: { $0.severity == .error })),
                            "Expected no errors for named companion factory, got: \(sampleDiags.map(\.code))"
                        )

            }

        }
    }




    /// Verify `Foo.create()` companion factory resolves through sema with no errors.




    /// Verify `Foo.MAX_COUNT` const val access resolves through sema with no errors.




    /// Combined: factory function + const val in the same companion, used from main.




    /// Verify companion factory + const val lowers to KIR with companion init synthesized.


    @Test func testCompanionObjectKIRLoweringScenarios() throws {
        let sources = [
            """
            class Foo0(val x: Int) {
                companion object {
                    const val MAX_COUNT: Int = 100
                    fun create(): Foo0 = Foo0(0)
                }
            }
            fun main0() {
                val f: Foo0 = Foo0.create()
                val m: Int = Foo0.MAX_COUNT
            }
            """,
            """
            class Host1 {
                companion object {
                    val counter: Int = 1
                    fun get(): Int = counter
                }
            }
            fun main1() {
                val v: Int = Host1.get()
            }
            """,
            """
            class Config2 {
                companion object {
                    val defaultTimeout: Int = 30
                }
            }
            fun main2(): Int = Config2.defaultTimeout
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            #expect(
                !(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )

            let module = try #require(ctx.kir)
            let functionNames = findAllKIRFunctions(in: module).map { function in
                ctx.interner.resolve(function.name)
            }

            // Foo0: companion initializer and create function are lowered
            #expect(
                functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
                "Expected synthesized companion initializer, got: \(functionNames)"
            )
            #expect(
                functionNames.contains("create"),
                "Expected companion function 'create' in KIR, got: \(functionNames)"
            )

            // Host1: exactly one companion singleton init function is synthesized
            do {
                let expectedInitName = try companionInitializerName(forOwnerNamed: "Host1", in: ctx)
                let companionInits = findAllKIRFunctions(in: module).compactMap { function -> String? in
                    let name = ctx.interner.resolve(function.name)
                    return name == expectedInitName ? name : nil
                }
                #expect(
                    companionInits.count == 1,
                    "Expected exactly one Host1 companion initializer, got \(companionInits.count): \(companionInits)"
                )
            }

            // Config2: companion init body has a copy for property initialization
            do {
                let expectedInitName = try companionInitializerName(forOwnerNamed: "Config2", in: ctx)
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
    }



    /// Verify exactly one companion singleton init function is synthesized.



    /// Named companion object should resolve factory calls via `ClassName.factoryFn()`.




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
