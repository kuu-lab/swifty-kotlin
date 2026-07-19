#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-PATH-FN-039: kotlin.io.path.PathWalkOption enum
//
// Focused coverage for the synthetic `kotlin.io.path.PathWalkOption` enum class.
// The enum is registered by `HeaderHelpers+SyntheticPathStubs+TypeCreation.swift`
// via `ensurePathWalkOptionEnum`, and its two entries (BREADTH_FIRST, FOLLOW_LINKS)
// are exposed as fields whose `propertyType` is the enum class type itself so that
// `PathWalkOption.BREADTH_FIRST`-style member references resolve through
// `resolveClassNameMemberValue`.

@Suite
struct PathWalkOptionEnumTests {

    // MARK: Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private static let allEntries = ["BREADTH_FIRST", "FOLLOW_LINKS"]

    // MARK: - Enum class declaration shape

    @Test func testPathWalkOptionIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.path.PathWalkOption must be registered as a synthetic symbol"
        )
        #expect(
            sema.symbols.symbol(symbol)?.kind == .enumClass,
            "PathWalkOption must be registered as enumClass (not regular class)"
        )
    }

    @Test func testPathWalkOptionIsParentedToKotlinIOPathPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))

        let parent = try #require(
            sema.symbols.parentSymbol(for: symbol),
            "PathWalkOption must be parented to the kotlin.io.path package symbol"
        )
        let parentInfo = try #require(sema.symbols.symbol(parent))
        #expect(parentInfo.kind == .package)
        #expect(
            parentInfo.fqName.map { interner.resolve($0) } == ["kotlin", "io", "path"],
            "PathWalkOption's parent must be the kotlin.io.path package"
        )
    }

    @Test func testPathWalkOptionHasCorrectPropertyType() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(
            sema.symbols.propertyType(for: symbol) == expectedType,
            "PathWalkOption's propertyType must be the enum class type itself"
        )
    }

    // MARK: - Enum entries

    @Test func testBothPathWalkOptionEntriesAreRegisteredAsFields() throws {
        let (sema, interner) = try makeSema()
        for entry in Self.allEntries {
            let fqName = ["kotlin", "io", "path", "PathWalkOption", entry].map { interner.intern($0) }
            let symbol = try #require(
                sema.symbols.lookup(fqName: fqName),
                "PathWalkOption.\(entry) must be present in the symbol table"
            )
            #expect(
                sema.symbols.symbol(symbol)?.kind == .field,
                "PathWalkOption.\(entry) must be registered as field (enum entry)"
            )
        }
    }

    @Test func testPathWalkOptionEntryPropertyTypesAreEnumType() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try #require(
                sema.symbols.lookup(fqName: fqName),
                "PathWalkOption.\(entry) must exist"
            )
            #expect(
                sema.symbols.propertyType(for: entrySymbol) == expectedType,
                "PathWalkOption.\(entry) propertyType must equal PathWalkOption (so member resolution works)"
            )
        }
    }

    @Test func testPathWalkOptionEntriesAreParentedToEnumClass() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try #require(sema.symbols.lookup(fqName: fqName))
            #expect(
                sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol,
                "PathWalkOption.\(entry) must be parented to the PathWalkOption enum class"
            )
        }
    }

    @Test func testPathWalkOptionHasExactlyTwoEntries() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let children = sema.symbols.children(ofFQName: enumFQName)
        let fieldNames: Set<String> = Set(
            children.compactMap { child -> String? in
                guard let info = sema.symbols.symbol(child), info.kind == .field else {
                    return nil
                }
                return info.fqName.last.map { interner.resolve($0) }
            }
        )
        #expect(
            fieldNames == Set(Self.allEntries),
            "PathWalkOption enum entries must exactly match the Kotlin stdlib spec (BREADTH_FIRST, FOLLOW_LINKS)"
        )
    }

    // MARK: - Member resolution in source

    @Test func testPathWalkOptionMemberAccessResolves() throws {
        let source = """
        import kotlin.io.path.PathWalkOption

        fun pickBreadthFirst(): PathWalkOption = PathWalkOption.BREADTH_FIRST
        fun pickFollowLinks(): PathWalkOption = PathWalkOption.FOLLOW_LINKS
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let messages = errors.map { "\($0.code): \($0.message)" }
            #expect(
                errors.isEmpty,
                Comment(rawValue: "Expected every PathWalkOption entry to resolve cleanly, got: \(messages)")
            )
        }
    }

    @Test func testPathWalkOptionUsedInWhenExpressionResolves() throws {
        let source = """
        import kotlin.io.path.PathWalkOption

        fun describe(option: PathWalkOption): String {
            return when (option) {
                PathWalkOption.BREADTH_FIRST -> "breadth-first"
                PathWalkOption.FOLLOW_LINKS -> "follow-links"
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "PathWalkOption in when expression should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
#endif
