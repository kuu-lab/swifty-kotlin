#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Tests for companion object support (P5-73).
///
/// Fix 1 – TypeCheckHelpers.resolveTypeRef short-name fallback:
///   Packaged types referenced by simple name (e.g. `Foo` instead of
///   `test.Foo`) must resolve during type-checking.
///
/// Fix 2 – Parser unnamed companion object:
///   `companion object { ... }` (without a name) must not emit
///   "Expected declaration name" warning (KSWIFTK-PARSE-0002).
@Suite struct CompanionObjectTests {

    @Test func testCompanionObjectSema() throws {
        let sources: [String] = [
            // testPackagedClassInCompanionFunctionReturnTypeResolves
            """
            package sample0
                    class Foo
                    class Bar {
                        companion object {
                            fun create(): Foo = Foo()
                        }
                    }

            """,

            // testPackagedClassInRegularFunctionReturnTypeResolves
            """
            package sample1
                    class Foo
                    fun makeFoo(): Foo = Foo()

            """,

            // testPackagedClassInFunctionParameterTypeResolves
            """
            package sample2
                    class Foo
                    fun takeFoo(f: Foo): Int = 1

            """,

            // testNonPackagedTypeResolutionStillWorks
            """
            package sample3
                    class Foo
                    fun makeFoo(): Foo = Foo()

            """,

            // testBuiltinTypesResolveInPackagedContext
            """
            package sample4
                    fun intFn(): Int = 1
                    fun strFn(): String = "hello"
                    fun boolFn(): Boolean = true

            """,

            // testUnresolvedTypeStillReportsDiagnostic
            """
            package sample5
                    fun bad(): NoSuchType = 1

            """,

            // testMultiplePackagedClassesResolveIndependently
            """
            package sample6
                    class Alpha
                    class Beta
                    fun makeAlpha(): Alpha = Alpha()
                    fun makeBeta(): Beta = Beta()

            """,

            // testUnnamedCompanionInPackagedClassResolvesReturnType
            """
            package sample7
                    class Result
                    class Builder {
                        companion object {
                            fun build(): Result = Result()
                        }
                    }

            """,

            // testNamedCompanionInPackagedClassResolvesReturnType
            """
            package sample8
                    class Config
                    class App {
                        companion object Factory {
                            fun defaultConfig(): Config = Config()
                        }
                    }

            """,

            // testCompanionObjectWithMultipleFunctions
            """
            package sample9
                    class Item
                    class Container {
                        companion object {
                            fun empty(): Int = 0
                            fun single(): Item = Item()
                        }
                    }

            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testPackagedClassInCompanionFunctionReturnTypeResolves

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testPackagedClassInRegularFunctionReturnTypeResolves

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testPackagedClassInFunctionParameterTypeResolves

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testNonPackagedTypeResolutionStillWorks

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testBuiltinTypesResolveInPackagedContext

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testUnresolvedTypeStillReportsDiagnostic

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testMultiplePackagedClassesResolveIndependently

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testUnnamedCompanionInPackagedClassResolvesReturnType

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testNamedCompanionInPackagedClassResolvesReturnType

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }
            // testCompanionObjectWithMultipleFunctions

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sampleDiags)

            }

        }
    }


    // MARK: - Fix 1: Type resolution short-name fallback for packaged types




    // MARK: - Fix 2: Parser unnamed companion object



    @Test func testUnnamedCompanionObjectProducesNoParseWarning() throws {
        let source = """
        class Foo {
            companion object {
                fun create(): Int = 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }


    @Test func testNamedCompanionObjectProducesNoParseWarning() throws {
        let source = """
        class Foo {
            companion object Factory {
                fun create(): Int = 1
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }


    @Test func testNonCompanionObjectWithNameProducesNoWarning() throws {
        let source = """
        object MySingleton {
            fun value(): Int = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: ctx)
    }



    // MARK: - Combined: companion object in packaged context




    // MARK: - KIR emission for companion object



    @Test func testCompanionObjectKIREmissionSucceeds() throws {
        let source = """
        class Foo {
            companion object {
                fun value(): Int = 42
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 1)
    }


    @Test func testPackagedCompanionObjectKIREmissionSucceeds() throws {
        let source = """
        package test
        class Foo
        class Bar {
            companion object {
                fun create(): Foo = Foo()
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError)
    }

    // MARK: - Synthetic builtin companion handle (KUU-3675)

    /// KUU-3675: synthetic companions such as `kotlin.String.Companion` have
    /// no AST object declaration, so no initializer was ever synthesized for
    /// them and their global root slots stayed zero. Any nominal cast on the
    /// companion value (the erased-boundary cast inside a function-value
    /// adapter) then threw at runtime. `synthesizeUninitializedCompanionHandles`
    /// must emit an eager `__companion_init` that allocates and stores a real
    /// singleton handle, and `main` must call it before user code runs.
    @Test func testSyntheticCompanionHandleInitializerIsEmitted() throws {
        let source = """
        fun <T> T.f(E: (y: T) -> String): Boolean = E(this).isEmpty()
        fun main() = println((String).f { v -> "" })
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let kotlinName = interner.intern("kotlin")
        let stringName = interner.intern("String")
        guard let stringSymbol = sema.symbols.lookup(fqName: [kotlinName, stringName]),
              let companionSymbol = sema.symbols.companionObjectSymbol(for: stringSymbol)
        else {
            Issue.record("kotlin.String.Companion was not registered")
            return
        }

        #expect(module.arena.declarations.contains { declaration in
            guard case let .global(global) = declaration else { return false }
            return global.symbol == companionSymbol
        })

        let expectedName = interner.intern(
            "__companion_init_\(stringSymbol.rawValue)_\(companionSymbol.rawValue)"
        )
        let initFunction = try #require(
            module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      function.name == expectedName
                else { return nil }
                return function
            }.first,
            "no __companion_init function was synthesized for kotlin.String.Companion"
        )
        #expect(initFunction.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
            return interner.resolve(callee) == "kk_object_new"
        })
        #expect(initFunction.body.contains { instruction in
            guard case let .storeGlobal(_, symbol) = instruction else { return false }
            return symbol == companionSymbol
        })

        let mainCallsInitializer = module.arena.declarations.contains { declaration in
            guard case let .function(function) = declaration,
                  interner.resolve(function.name) == "main"
            else { return false }
            return function.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == initFunction.symbol
            }
        }
        #expect(mainCallsInitializer)
    }

}
#endif
