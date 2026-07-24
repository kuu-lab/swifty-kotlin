#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Negative tests to ensure the array-erase heuristic (which previously typed
/// collection HOF results as `Any`) is not reintroduced.
///
/// Each test verifies that a specific collection higher-order function resolves
/// to a synthetic stub and is callable on a `List<String>` receiver without
/// producing a type-mismatch diagnostic.  If the array-erase heuristic is ever
/// re-introduced, these calls would either fail to resolve or silently erase
/// the result type — which the golden tests would also catch.
@Suite
struct ArrayEraseHeuristicNegativeTests {

    // MARK: - HOF stub existence (symbol table)

    /// Verify that all target HOF members are registered as synthetic stubs,
    /// so they cannot be silently removed without test breakage.
    @Test func testCollectionHOFSyntheticStubsExist() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let listFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            // partition is still registered as an explicit synthetic member stub.
            // mapIndexed is now provided by bundled Kotlin source (top-level extension).
            let collectionsFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let mapIndexedSource = sema.symbols.lookup(
                fqName: collectionsFQ + [ctx.interner.intern("mapIndexed")]
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
                fqName: listFQ + [ctx.interner.intern("partition")]
            )
            #expect(
                partitionSymbolID != nil,
                "Expected synthetic List member 'partition' to be registered"
            )
        }
    }

    // MARK: - HOF call resolution (no type-mismatch diagnostic)

    /// mapIndexed call on List<String> must resolve without type error.
    @Test func testMapIndexedCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.mapIndexed { index, item -> item.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// flatMap call on List<String> must resolve without type error.
    @Test func testFlatMapCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.flatMap { listOf(it) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associate call on List<String> must resolve without type error.
    @Test func testAssociateCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associate { it to it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associateBy call on List<String> must resolve without type error.
    @Test func testAssociateByCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associateBy { it.first() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// associateWith call on List<String> must resolve without type error.
    @Test func testAssociateWithCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.associateWith { it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// groupBy call on List<String> must resolve without type error.
    @Test func testGroupByCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.groupBy { it.length }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// partition call on List<String> must resolve without type error.
    @Test func testPartitionCallResolvesWithoutTypeError() throws {
        let source = """
        fun test(values: List<String>) {
            values.partition { it.length > 3 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - listOf() type preservation

    /// Verify that listOf(1, 2, 3) is typed as a collection (not erased to Any).
    @Test func testListOfIntIsNotErasedToAny() throws {
        let source = """
        fun test() {
            val x = listOf(1, 2, 3)
            x.contains(2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // If erased to Any, contains() would fail to resolve.
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-VAR-OUT", in: ctx)
        }
    }
}
#endif
