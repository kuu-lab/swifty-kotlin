@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-IO-PATH-FN-039: kotlin.io.path.PathWalkOption enum
//
// Focused coverage for the synthetic `kotlin.io.path.PathWalkOption` enum class.
// The enum is registered by `HeaderHelpers+SyntheticPathStubs+TypeCreation.swift`
// via `ensurePathWalkOptionEnum`, and its two entries (BREADTH_FIRST, FOLLOW_LINKS)
// are exposed as fields whose `propertyType` is the enum class type itself so that
// `PathWalkOption.BREADTH_FIRST`-style member references resolve through
// `resolveClassNameMemberValue`.

final class PathWalkOptionEnumTests: XCTestCase {

    // MARK: Helpers

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private static let allEntries = ["BREADTH_FIRST", "FOLLOW_LINKS"]

    // MARK: - Enum class declaration shape

    func testPathWalkOptionIsRegisteredAsEnumClass() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.io.path.PathWalkOption must be registered as a synthetic symbol"
        )
        XCTAssertEqual(
            sema.symbols.symbol(symbol)?.kind,
            .enumClass,
            "PathWalkOption must be registered as enumClass (not regular class)"
        )
    }

    func testPathWalkOptionIsParentedToKotlinIOPathPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))

        let parent = try XCTUnwrap(
            sema.symbols.parentSymbol(for: symbol),
            "PathWalkOption must be parented to the kotlin.io.path package symbol"
        )
        let parentInfo = try XCTUnwrap(sema.symbols.symbol(parent))
        XCTAssertEqual(parentInfo.kind, .package)
        XCTAssertEqual(
            parentInfo.fqName.map { interner.resolve($0) },
            ["kotlin", "io", "path"],
            "PathWalkOption's parent must be the kotlin.io.path package"
        )
    }

    func testPathWalkOptionHasCorrectPropertyType() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(
            sema.symbols.propertyType(for: symbol),
            expectedType,
            "PathWalkOption's propertyType must be the enum class type itself"
        )
    }

    // MARK: - Enum entries

    func testBothPathWalkOptionEntriesAreRegisteredAsFields() throws {
        let (sema, interner) = try makeSema()
        for entry in Self.allEntries {
            let fqName = ["kotlin", "io", "path", "PathWalkOption", entry].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "PathWalkOption.\(entry) must be present in the symbol table"
            )
            XCTAssertEqual(
                sema.symbols.symbol(symbol)?.kind,
                .field,
                "PathWalkOption.\(entry) must be registered as field (enum entry)"
            )
        }
    }

    func testPathWalkOptionEntryPropertyTypesAreEnumType() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))
        let expectedType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fqName),
                "PathWalkOption.\(entry) must exist"
            )
            XCTAssertEqual(
                sema.symbols.propertyType(for: entrySymbol),
                expectedType,
                "PathWalkOption.\(entry) propertyType must equal PathWalkOption (so member resolution works)"
            )
        }
    }

    func testPathWalkOptionEntriesAreParentedToEnumClass() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "io", "path", "PathWalkOption"].map { interner.intern($0) }
        let enumSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: enumFQName))

        for entry in Self.allEntries {
            let fqName = enumFQName + [interner.intern(entry)]
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
            XCTAssertEqual(
                sema.symbols.parentSymbol(for: entrySymbol),
                enumSymbol,
                "PathWalkOption.\(entry) must be parented to the PathWalkOption enum class"
            )
        }
    }

    func testPathWalkOptionHasExactlyTwoEntries() throws {
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
        XCTAssertEqual(
            fieldNames,
            Set(Self.allEntries),
            "PathWalkOption enum entries must exactly match the Kotlin stdlib spec (BREADTH_FIRST, FOLLOW_LINKS)"
        )
    }

    // MARK: - Member resolution in source

    func testPathWalkOptionMemberAccessResolves() throws {
        let source = """
        import kotlin.io.path.PathWalkOption

        fun pickBreadthFirst(): PathWalkOption = PathWalkOption.BREADTH_FIRST
        fun pickFollowLinks(): PathWalkOption = PathWalkOption.FOLLOW_LINKS
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            XCTAssertTrue(
                errors.isEmpty,
                "Expected every PathWalkOption entry to resolve cleanly, got: "
                    + "\(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }

    func testPathWalkOptionUsedInWhenExpressionResolves() throws {
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
            XCTAssertTrue(
                errors.isEmpty,
                "PathWalkOption in when expression should resolve: \(errors.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
