#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

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
                            !sampleDiags.hasError,
                            "Expected no sema errors for Foo.create(), got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionConstValAccessResolvesEndToEnd

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)

                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors for Foo.MAX_COUNT, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testCompanionFactoryAndConstValCombinedEndToEnd

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)

                        #expect(
                            !sampleDiags.hasError,
                            "Expected no sema errors, got: \(sampleDiags.map(\.code))"
                        )

            }
            // testNamedCompanionFactoryResolvesEndToEnd

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)

                        #expect(
                            !sampleDiags.hasError,
                            "Expected no errors for named companion factory, got: \(sampleDiags.map(\.code))"
                        )

            }

        }
    }

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
            !ctx.diagnostics.hasError,
            "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )

        let module = try #require(ctx.kir)
        let functionNames = findAllKIRFunctions(in: module).map { function in
            ctx.interner.resolve(function.name)
        }

        #expect(
            functionNames.contains(where: { $0.hasPrefix("__companion_init_") }),
            "Expected synthesized companion initializer, got: \(functionNames)"
        )

        #expect(
            functionNames.contains("create"),
            "Expected companion function 'create' in KIR, got: \(functionNames)"
        )
    }

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
            !ctx.diagnostics.hasError,
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
            !ctx.diagnostics.hasError,
            "Expected no errors after full lowering, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }

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
                !ctx.diagnostics.hasError,
                "Expected no KIR errors, got: \(ctx.diagnostics.diagnostics.map(\.code))"
            )

            let module = try #require(ctx.kir)
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
