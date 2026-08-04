@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-TEXT-TYPE-012: kotlin.text.RegexOption enum
//
// Focused coverage for the synthetic `kotlin.text.RegexOption` enum class.
// The enum is registered as a synthetic symbol by
// `HeaderHelpers+SyntheticRegexStubs.swift` via `ensureRegexOptionEnumClass`,
// and its entries (IGNORE_CASE, MULTILINE, LITERAL, UNIX_LINES, COMMENTS,
// DOT_MATCHES_ALL, CANON_EQ) are exposed as fields whose static `propertyType`
// is the enum class type itself so that `RegexOption.IGNORE_CASE`-style
// member references resolve through `resolveClassNameMemberValue`.
//
// Wider Regex API surface (constructors, members, properties) is covered by
// `RegexAPISurfaceInventoryTests`. This file focuses purely on the enum
// declaration shape and member resolution.

@Suite
struct RegexOptionEnumTests {

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

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    /// Canonical entry list matching the Kotlin stdlib `RegexOption` enum
    /// (mirrors `ensureRegexOptionEnumClass` in
    /// `HeaderHelpers+SyntheticRegexStubs.swift`).
    private static let allEntries = [
        "IGNORE_CASE",
        "MULTILINE",
        "LITERAL",
        "UNIX_LINES",
        "COMMENTS",
        "DOT_MATCHES_ALL",
        "CANON_EQ",
    ]

    // MARK: - Enum class declaration shape

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testRegexOptionIsRegisteredAsEnumClass
            """
            package sample0
            fun noop() {}
            """,
            // testRegexOptionIsParentedToKotlinTextPackage
            """
            package sample1
            fun noop() {}
            """,
            // testAllSevenRegexOptionEntriesAreRegisteredAsFields
            """
            package sample2
            fun noop() {}
            """,
            // testRegexOptionEntryPropertyTypesAreEnumType
            """
            package sample3
            fun noop() {}
            """,
            // testRegexOptionEntriesAreParentedToEnumClass
            """
            package sample4
            fun noop() {}
            """,
            // testRegexOptionDoesNotRegisterUnexpectedEntries
            """
            package sample5
            fun noop() {}
            """,
            // testRegexOptionMemberAccessResolves
            """
            package sample6

                    import kotlin.text.RegexOption

                    fun pickIgnoreCase(): RegexOption = RegexOption.IGNORE_CASE
                    fun pickMultiline(): RegexOption = RegexOption.MULTILINE
                    fun pickLiteral(): RegexOption = RegexOption.LITERAL
                    fun pickUnixLines(): RegexOption = RegexOption.UNIX_LINES
                    fun pickComments(): RegexOption = RegexOption.COMMENTS
                    fun pickDotMatchesAll(): RegexOption = RegexOption.DOT_MATCHES_ALL
                    fun pickCanonEq(): RegexOption = RegexOption.CANON_EQ

            """,
            // testRegexOptionPassesThroughRegexConstructor
            """
            package sample7

                    import kotlin.text.Regex
                    import kotlin.text.RegexOption

                    fun makeIgnoreCaseRegex(): Regex = Regex("hello", RegexOption.IGNORE_CASE)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testRegexOptionIsRegisteredAsEnumClass ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let fqName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
                let symbol = try #require(
                    sema.symbols.lookup(fqName: fqName),
                    "kotlin.text.RegexOption must be registered as a synthetic symbol"
                )
                #expect(
                    sema.symbols.symbol(symbol)?.kind == .enumClass,
                    "RegexOption must be registered as enumClass (not regular class)"
                )

            }

            // === testRegexOptionIsParentedToKotlinTextPackage ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let fqName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookup(fqName: fqName))

                let parent = try #require(
                    sema.symbols.parentSymbol(for: symbol),
                    "RegexOption must be parented to the kotlin.text package symbol"
                )
                let parentInfo = try #require(sema.symbols.symbol(parent))
                #expect(parentInfo.kind == .package)
                #expect(
                    parentInfo.fqName.map { interner.resolve($0) } == ["kotlin", "text"],
                    "RegexOption's parent must be the kotlin.text package"
                )

            }

            // === testAllSevenRegexOptionEntriesAreRegisteredAsFields ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                for entry in Self.allEntries {
                    let fqName = ["kotlin", "text", "RegexOption", entry].map { interner.intern($0) }
                    let symbol = try #require(
                        sema.symbols.lookup(fqName: fqName),
                        "RegexOption.\(entry) must be present in the symbol table"
                    )
                    #expect(
                        sema.symbols.symbol(symbol)?.kind == .field,
                        "RegexOption.\(entry) must be registered as field (enum entry)"
                    )
                }

            }

            // === testRegexOptionEntryPropertyTypesAreEnumType ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
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
                        "RegexOption.\(entry) must exist"
                    )
                    #expect(
                        sema.symbols.propertyType(for: entrySymbol) == expectedType,
                        "RegexOption.\(entry) propertyType must equal RegexOption (so member resolution works)"
                    )
                }

            }

            // === testRegexOptionEntriesAreParentedToEnumClass ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))

                for entry in Self.allEntries {
                    let fqName = enumFQName + [interner.intern(entry)]
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: fqName))
                    #expect(
                        sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol,
                        "RegexOption.\(entry) must be parented to the RegexOption enum class"
                    )
                }

            }

            // === testRegexOptionDoesNotRegisterUnexpectedEntries ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let enumFQName = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
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
                    "RegexOption enum entries must exactly match the Kotlin stdlib spec"
                )

            }

            // === testRegexOptionMemberAccessResolves ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let errors = sample6Diagnostics.filter { $0.severity == .error }
                let v = errors.map { "\($0.code): \($0.message)" }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Expected every RegexOption entry to resolve cleanly, got: \(v)")
                )

            }

            // === testRegexOptionPassesThroughRegexConstructor ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                // Round-trip: confirm that an entry can flow into the
                // `Regex(String, RegexOption)` overload registered alongside the enum.
                let errors = sample7Diagnostics.filter { $0.severity == .error }
                let v = errors.map { "\($0.code): \($0.message)" }
                #expect(
                    errors.isEmpty,
                    Comment(rawValue: "Regex(String, RegexOption) must resolve cleanly, got: \(v)")
                )

            }

        }
    }

}
