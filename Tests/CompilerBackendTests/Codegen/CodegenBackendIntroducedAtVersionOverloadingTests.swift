#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendIntroducedAtVersionOverloadingTests {
    @Test
    func trailingLambdaWrappersPreserveParameterOrderAndLink() throws {
        let source = """
        @file:OptIn(ExperimentalVersionOverloading::class)

        fun trailingVersioned(
            value: String = "O",
            @IntroducedAt("1") suffix: String = "K",
            @IntroducedAt("2") punctuation: String = "!",
            transform: (String) -> String,
        ): String = transform(value + suffix + punctuation)

        fun numericallySorted(
            value: Int = 0,
            @IntroducedAt("2") second: Int = 2,
            @IntroducedAt("10") tenth: Int = 10,
        ): Int = value + second + tenth

        fun main() {
            println(trailingVersioned { it })
            println(trailingVersioned("A", "B") { it })
            println(trailingVersioned("A", "B", "C") { it + "?" })
            println(numericallySorted())
        }
        """
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("introduced-at-trailing-\(UUID().uuidString)").path

        try withTemporaryFile(contents: source) { inputPath in
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "IntroducedAtTrailingLambda",
                outputPath: outputBase
            )
            let sema = try #require(context.sema)
            let module = try #require(context.kir)

            func functions(named name: String) -> [(KIRFunction, FunctionSignature)] {
                module.arena.declarations.compactMap { declaration in
                    guard case let .function(function) = declaration,
                          function.name == context.interner.intern(name),
                          sema.symbols.symbol(function.symbol) != nil,
                          let signature = sema.symbols.functionSignature(for: function.symbol)
                    else {
                        return nil
                    }
                    return (function, signature)
                }
            }

            let trailingFunctions = functions(named: "trailingVersioned")
            let trailingWrappers = trailingFunctions.filter { function, _ in
                sema.symbols.symbol(function.symbol)?.flags.contains(.synthetic) == true
            }
                .sorted { $0.1.parameterTypes.count < $1.1.parameterTypes.count }
            #expect(trailingWrappers.map { $0.1.parameterTypes.count } == [2, 3])
            let trailingParameterNames = trailingWrappers.map { _, signature in
                signature.valueParameterSymbols.map { symbol in
                    sema.symbols.symbol(symbol).map { context.interner.resolve($0.name) } ?? "<missing>"
                }
            }
            #expect(trailingParameterNames == [["value", "transform"], ["value", "suffix", "transform"]])
            #expect(trailingWrappers.allSatisfy { $0.1.valueParameterHasDefaultValues.first == true })

            let numericWrappers = functions(named: "numericallySorted")
                .filter { function, _ in
                    sema.symbols.symbol(function.symbol)?.flags.contains(.synthetic) == true
                }
                .sorted { $0.1.parameterTypes.count < $1.1.parameterTypes.count }
            #expect(numericWrappers.map { $0.1.valueParameterSymbols.count } == [1, 2])

            let defaultStubCount = module.arena.declarations.reduce(into: 0) { count, declaration in
                guard case let .function(function) = declaration,
                      context.interner.resolve(function.name) == "trailingVersioned$default"
                else {
                    return
                }
                count += 1
            }
            #expect(defaultStubCount == 3)

            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout == """
            OK!
            AB!
            ABC?
            12
            """ + "\n")
        }
    }

    @Test
    func contextCompanionConstructorsAndValueClassesLink() throws {
        let source = """
        @file:OptIn(ExperimentalVersionOverloading::class, kotlin.ExperimentalContextParameters::class)

        context(prefix: String)
        fun contextVersioned(
            value: String = "O",
            @IntroducedAt("1") suffix: String = "K",
        ): String = prefix + value + suffix

        class VersionedHost {
            companion {
                fun companionBlockFun(number: Int, @IntroducedAt("1") suffix: String = "B"): String =
                    "Companion" + number + suffix
            }
        }

        class PrimaryVersionedConstructor(
            val prefix: String,
            @IntroducedAt("1") val suffix: String = "K",
        )

        class SecondaryVersionedConstructor {
            val value: String

            constructor(
                prefix: String = "O",
                @IntroducedAt("1") suffix: String = "K",
            ) {
                value = prefix + suffix
            }
        }

        @JvmInline
        value class VersionedToken(val value: String)

        fun renderVersionedTokens(
            @IntroducedAt("1") token: VersionedToken = VersionedToken("K"),
            @IntroducedAt("2") nullableToken: VersionedToken? = null,
        ): String = token.value + (nullableToken?.value ?: "N")

        @JvmInline
        value class VersionedValue(val value: Int) {
            constructor(
                text: String,
                @IntroducedAt("1") offset: Int = 0,
            ) : this(text.length + offset)

            fun render(@IntroducedAt("1") suffix: String = "!"): String = value.toString() + suffix
        }

        fun main() {
            println(with("P") { contextVersioned() })
            println(with("P") { contextVersioned("A", "B") })
            println(VersionedHost.companionBlockFun(1))
            println(PrimaryVersionedConstructor("O").suffix)
            println(SecondaryVersionedConstructor().value)
            println(renderVersionedTokens())
            println(renderVersionedTokens(VersionedToken("A")))
            println(renderVersionedTokens(VersionedToken("A"), VersionedToken("B")))
            println(VersionedValue("OK").value)
            println(VersionedValue("OK", 1).value)
            println(VersionedValue(2).render())
            println(VersionedValue(2).render("?"))
        }
        """
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("introduced-at-context-\(UUID().uuidString)").path

        try withTemporaryFile(contents: source) { inputPath in
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "IntroducedAtContextAndConstructors",
                outputPath: outputBase,
                frontendFlags: ["explicit-context-arguments"]
            )
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout == "POK\nPAB\nCompanion1B\nK\nOK\nKN\nAN\nAB\n2\n3\n2!\n2?\n")
        }
    }

    @Test
    func reifiedDefaultVersionWrapperCarriesTypeTokens() throws {
        let source = """
        @file:OptIn(ExperimentalVersionOverloading::class)

        inline fun <reified T> reifiedDefault(
            @IntroducedAt("1") value: T? = null,
        ): String = if (T::class == String::class) "String:$value" else "Other:$value"

        fun main() {
            println(reifiedDefault<String>())
        }
        """
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("introduced-at-reified-\(UUID().uuidString)").path

        try withTemporaryFile(contents: source) { inputPath in
            let context = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "IntroducedAtReifiedDefault",
                outputPath: outputBase
            )
            let sema = try #require(context.sema)
            let module = try #require(context.kir)
            let wrapper = try #require(module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration,
                      function.name == context.interner.intern("reifiedDefault"),
                      let symbol = sema.symbols.symbol(function.symbol),
                      symbol.flags.contains(.synthetic),
                      let signature = sema.symbols.functionSignature(for: function.symbol),
                      signature.parameterTypes.isEmpty
                else {
                    return nil
                }
                return function
            }.first)
            #expect(wrapper.params.count == 2)

            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout == "String:null\n")
        }
    }
}
#endif
