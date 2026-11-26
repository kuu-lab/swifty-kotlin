#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ArrayEraseHeuristicNegativeTests {

    @Test
    func testArrayEraseHeuristics() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
            """
            package sample1

                    fun test(values: List<String>) {
                        values.mapIndexed { index, item -> item.length }
                    }

            """,
            """
            package sample2

                    fun test(values: List<String>) {
                        values.flatMap { listOf(it) }
                    }

            """,
            """
            package sample3

                    fun test(values: List<String>) {
                        values.associate { it to it.length }
                    }

            """,
            """
            package sample4

                    fun test(values: List<String>) {
                        values.associateBy { it.first() }
                    }

            """,
            """
            package sample5

                    fun test(values: List<String>) {
                        values.associateWith { it.length }
                    }

            """,
            """
            package sample6

                    fun test(values: List<String>) {
                        values.groupBy { it.length }
                    }

            """,
            """
            package sample7

                    fun test(values: List<String>) {
                        values.partition { it.length > 3 }
                    }

            """,
            """
            package sample8

                    fun test() {
                        val x = listOf(1, 2, 3)
                        x.contains(2)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = (sema, interner)

            do {
                let sema = try #require(ctx.sema)
                let collectionsFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let mapIndexedSource = sema.symbols.lookup(
                    fqName: collectionsFQ + [interner.intern("mapIndexed")]
                )
                #expect(
                    mapIndexedSource != nil,
                    "Expected bundled source 'mapIndexed' to be registered"
                )
                if let mapIndexedSource {
                    let symbol = try #require(sema.symbols.symbol(mapIndexedSource))
                    #expect(!symbol.flags.contains(.synthetic), "mapIndexed must be a real bundled source declaration")
                }

                let partitionSymbolID = sema.symbols.lookup(
                    fqName: collectionsFQ + [interner.intern("partition")]
                )
                #expect(
                    partitionSymbolID != nil,
                    "Expected bundled source 'partition' to be registered"
                )
                if let partitionSymbolID {
                    let symbol = try #require(sema.symbols.symbol(partitionSymbolID))
                    #expect(!symbol.flags.contains(.synthetic), "partition must be a real bundled source declaration")
                }
            }

            do {
                let samplePath = paths[1]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[2]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[3]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[4]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[5]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[6]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[7]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            do {
                let samplePath = paths[8]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
                assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
            }
        }
    }
}
#endif
