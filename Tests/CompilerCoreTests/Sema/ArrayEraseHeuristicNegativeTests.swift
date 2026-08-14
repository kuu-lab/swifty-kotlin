#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Negative tests to ensure the array-erase heuristic (which previously typed
/// collection HOF results as `Any`) is not reintroduced.
///
/// Each test verifies that a specific collection higher-order function resolves
/// (via bundled source or synthetic stub) and is callable on a `List<String>`
/// receiver without producing a type-mismatch diagnostic.  If the array-erase
/// heuristic is ever re-introduced, these calls would either fail to resolve or
/// silently erase the result type — which the golden tests would also catch.
@Suite
struct ArrayEraseHeuristicNegativeTests {

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testArrayEraseHeuristics() throws {
        let sources: [String] = [
            // source 0
            """
            fun noop() {}
            """,
            // source 1
            """
            package sample1

                    fun test(values: List<String>) {
                        values.mapIndexed { index, item -> item.length }
                    }

            """,
            // source 2
            """
            package sample2

                    fun test(values: List<String>) {
                        values.flatMap { listOf(it) }
                    }

            """,
            // source 3
            """
            package sample3

                    fun test(values: List<String>) {
                        values.associate { it to it.length }
                    }

            """,
            // source 4
            """
            package sample4

                    fun test(values: List<String>) {
                        values.associateBy { it.first() }
                    }

            """,
            // source 5
            """
            package sample5

                    fun test(values: List<String>) {
                        values.associateWith { it.length }
                    }

            """,
            // source 6
            """
            package sample6

                    fun test(values: List<String>) {
                        values.groupBy { it.length }
                    }

            """,
            // source 7
            """
            package sample7

                    fun test(values: List<String>) {
                        values.partition { it.length > 3 }
                    }

            """,
            // source 8
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

            // testCollectionHOFSyntheticStubsExist
            do {
                let sema = try #require(ctx.sema)
                // mapIndexed and partition are now provided by bundled Kotlin source (top-level extensions).
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

            // testMapIndexedCallResolvesWithoutTypeError
            do {
                let samplePath = paths[1]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testFlatMapCallResolvesWithoutTypeError
            do {
                let samplePath = paths[2]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testAssociateCallResolvesWithoutTypeError
            do {
                let samplePath = paths[3]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testAssociateByCallResolvesWithoutTypeError
            do {
                let samplePath = paths[4]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testAssociateWithCallResolvesWithoutTypeError
            do {
                let samplePath = paths[5]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testGroupByCallResolvesWithoutTypeError
            do {
                let samplePath = paths[6]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testPartitionCallResolvesWithoutTypeError
            do {
                let samplePath = paths[7]
                _ = samplePath
                #expect(
                        !diagnosticsForPath(samplePath, in: ctx).contains { $0.code == "KSWIFTK-TYPE-0001" },
                        "Expected no KSWIFTK-TYPE-0001 diagnostic for this source, got: \(diagnosticsForPath(samplePath, in: ctx))"
                    )
            }

            // testListOfIntIsNotErasedToAny
            do {
                let samplePath = paths[8]
                _ = samplePath
                // If erased to Any, contains() would fail to resolve.
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
