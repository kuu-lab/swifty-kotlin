#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-033: Validates that `kotlin.io.Reader.readText()` resolves
/// through Sema as an extension function on `java.io.Reader`. The synthetic
/// `Reader` supertype lets concrete reader values (currently `BufferedReader`
/// instances produced by `File.bufferedReader()`) participate in the call
/// without explicit upcasting.
///
/// Verifies:
///   1. The synthetic symbol is registered with the correct extension
///      receiver, parameter list, return type, and runtime link name
///      (`__kk_reader_readText`).
///   2. The function resolves end-to-end when invoked on a `BufferedReader`
///      value, including the common `File("...").bufferedReader().readText()`
///      chain and inside a `use { }` block.
@Suite
struct ReaderReadTextFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testReaderReadTextFunctionIsRegisteredOnReaderReceiver
            """
            package sample0
            fun noop() {}
            """,
            // testBufferedReaderIsRegisteredAsReaderSubtype
            """
            package sample1
            fun noop() {}
            """,
            // testReaderReadTextResolvesOnBufferedReaderChain
            """
            package sample2

                    import java.io.File

                    fun loadAll(): String {
                        return File("/dev/null").bufferedReader().readText()
                    }

            """,
            // testReaderReadTextReturnsStringInVariableBinding
            """
            package sample3

                    import java.io.File

                    fun loadAll(file: File): String {
                        val reader = file.bufferedReader()
                        val text: String = reader.readText()
                        reader.close()
                        return text
                    }

            """,
            // testReaderReadTextWorksInsideUseBlock
            """
            package sample4

                    import java.io.File

                    fun loadAllSafely(file: File): String {
                        return file.bufferedReader().use { reader ->
                            reader.readText()
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testReaderReadTextFunctionIsRegisteredOnReaderReceiver ===

            do {

                let sample0Path = paths[0]


                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "Sema should succeed on a trivial program: " +
                        "\(sample0Diagnostics.map(\.message))")
                )

                let readerFQ = ["java", "io", "Reader"].map { interner.intern($0) }
                let readerSymbol = try #require(
                    sema.symbols.lookup(fqName: readerFQ),
                    "java.io.Reader synthetic class should be registered"
                )
                let readerType = sema.types.make(.classType(ClassType(
                    classSymbol: readerSymbol, args: [], nullability: .nonNull
                )))

                let readTextFQ = ["kotlin", "io", "readText"].map { interner.intern($0) }
                let readTextSymbol = try #require(
                    sema.symbols.lookupAll(fqName: readTextFQ).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.receiverType == readerType
                            && signature.parameterTypes.isEmpty
                    },
                    "kotlin.io.Reader.readText() extension should be registered"
                )

                let signature = try #require(sema.symbols.functionSignature(for: readTextSymbol))
                #expect(
                    signature.returnType == sema.types.stringType,
                    "Reader.readText() must return non-null String"
                )
                #expect(
                    !(signature.isSuspend),
                    "Reader.readText() is not a suspend function"
                )
                #expect(
                    sema.symbols.externalLinkName(for: readTextSymbol) == "__kk_reader_readText",
                    "Reader.readText() must lower to __kk_reader_readText runtime entry"
                )

            }

            // === testBufferedReaderIsRegisteredAsReaderSubtype ===

            do {




                let readerFQ = ["java", "io", "Reader"].map { interner.intern($0) }
                let bufferedReaderFQ = ["java", "io", "BufferedReader"].map { interner.intern($0) }
                let readerSymbol = try #require(sema.symbols.lookup(fqName: readerFQ))
                let bufferedReaderSymbol = try #require(sema.symbols.lookup(fqName: bufferedReaderFQ))
                let directSupertypes = sema.symbols.directSupertypes(for: bufferedReaderSymbol)
                #expect(
                    directSupertypes.contains(readerSymbol),
                    Comment(rawValue: "BufferedReader must list Reader among its direct supertypes; got: \(directSupertypes)")
                )

            }

            // === testReaderReadTextResolvesOnBufferedReaderChain ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "File(...).bufferedReader().readText() should type-check, got: " +
                        "\(errors.map { "\($0.code): \($0.message)" })")
                )

            }

            // === testReaderReadTextReturnsStringInVariableBinding ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let errors = sample3Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Binding `val text: String = reader.readText()` should compile, got: " +
                        "\(errors.map { "\($0.code): \($0.message)" })")
                )

            }

            // === testReaderReadTextWorksInsideUseBlock ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let errors = sample4Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Reader.readText() inside a use { } block should compile, got: " +
                        "\(errors.map { "\($0.code): \($0.message)" })")
                )

            }

        }
    }

}

#endif
