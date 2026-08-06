#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-TYPE-005: kotlin.io.FileWalkDirection enum
//
// Focused coverage for the synthetic `kotlin.io.FileWalkDirection` enum class.
// The enum is registered by `HeaderHelpers+SyntheticFileWalkDirectionStubs.swift`
// via `registerSyntheticFileWalkDirectionStubs`, and its two entries
// (TOP_DOWN, BOTTOM_UP) are exposed as fields whose `propertyType` is the
// enum class type itself so that `FileWalkDirection.TOP_DOWN`-style member
// references resolve through `resolveClassNameMemberValue`.

@Suite
struct FileWalkDirectionEnumTests {

    /// Canonical entry list matching the Kotlin stdlib `FileWalkDirection` enum.
    private static let allEntries = ["TOP_DOWN", "BOTTOM_UP"]

    @Test
    func testFileWalkDirectionSema() throws {
        let sources: [String] = [
            """
            package sample0
            fun noop() {}
            """,
            """
            package sample1
            import kotlin.io.FileWalkDirection

            fun pickTopDown(): FileWalkDirection = FileWalkDirection.TOP_DOWN
            fun pickBottomUp(): FileWalkDirection = FileWalkDirection.BOTTOM_UP
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // testFileWalkDirectionIsRegisteredAsEnumClass
            do {
                let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "kotlin.io.FileWalkDirection must be registered as a synthetic symbol"
                )
                #expect(
                    sema.symbols.symbol(symbol)?.kind == .enumClass,
                    "FileWalkDirection must be registered as enumClass (not regular class)"
                )
            }

            // testFileWalkDirectionIsParentedToKotlinIOPackage
            do {
                let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))

                let parent = try #require(
                    sema.symbols.parentSymbol(for: symbol),
                    "FileWalkDirection must be parented to the kotlin.io package symbol"
                )
                let parentInfo = try #require(sema.symbols.symbol(parent))
                #expect(parentInfo.kind == .package)
                #expect(
                    parentInfo.fqName.map { interner.resolve($0) } == ["kotlin", "io"],
                    "FileWalkDirection's parent must be the kotlin.io package"
                )
            }

            // testFileWalkDirectionHasCorrectPropertyType
            do {
                let fqName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(
                    sema.symbols.propertyType(for: symbol) == expectedType,
                    "FileWalkDirection's propertyType must be the enum class type itself"
                )
            }

            // testBothFileWalkDirectionEntriesAreRegisteredAsFields
            do {
                for entry in Self.allEntries {
                    let fqName = ["kotlin", "io", "FileWalkDirection", entry].map { interner.intern($0) }
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: fqName),
                        "FileWalkDirection.\(entry) must be present in the symbol table"
                    )
                    #expect(
                        sema.symbols.symbol(symbol)?.kind == .field,
                        "FileWalkDirection.\(entry) must be registered as field (enum entry)"
                    )
                }
            }

            // testFileWalkDirectionEntryPropertyTypesAreEnumType
            do {
                let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
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
                        "FileWalkDirection.\(entry) must exist"
                    )
                    #expect(
                        sema.symbols.propertyType(for: entrySymbol) == expectedType,
                        "FileWalkDirection.\(entry) propertyType must equal FileWalkDirection (so member resolution works)"
                    )
                }
            }

            // testFileWalkDirectionEntriesAreParentedToEnumClass
            do {
                let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

                for entry in Self.allEntries {
                    let fqName = enumFQName + [interner.intern(entry)]
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: fqName))
                    #expect(
                        sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol,
                        "FileWalkDirection.\(entry) must be parented to the FileWalkDirection enum class"
                    )
                }
            }

            // testFileWalkDirectionHasExactlyTwoEntries
            do {
                let enumFQName = ["kotlin", "io", "FileWalkDirection"].map { interner.intern($0) }
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
                    "FileWalkDirection enum entries must exactly match the Kotlin stdlib spec (TOP_DOWN, BOTTOM_UP)"
                )
            }

            // testFileWalkDirectionMemberAccessResolves
            do {
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected every FileWalkDirection entry to resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
#endif
