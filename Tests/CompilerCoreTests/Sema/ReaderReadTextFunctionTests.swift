#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-033: Validates that `kotlin.io.Reader.readText()` resolves
/// through Sema as an extension function on `java.io.Reader`. The synthetic
/// `Reader` supertype lets concrete reader values (`BufferedReader`
/// instances) participate in the call without explicit upcasting.
///
/// Verifies:
///   1. The synthetic symbol is registered with the correct extension
///      receiver, parameter list, return type, and runtime link name
///      (`__kk_reader_readText`).
///   2. `BufferedReader` is registered as a `Reader` subtype in the symbol
///      table, so the extension resolves without explicit upcasting.
///
/// CLEANUP-STUB-107 removed `File.bufferedReader()`, which was this suite's
/// only in-repo way to obtain a `BufferedReader` from a path; the end-to-end
/// resolution cases that used to chain off of it (`File("...").bufferedReader().readText()`,
/// a `use { }` block, and a plain variable binding) were removed along with
/// it. The symbol-table checks below are unaffected since they don't need a
/// live `BufferedReader` value.
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

        }
    }

}

#endif
