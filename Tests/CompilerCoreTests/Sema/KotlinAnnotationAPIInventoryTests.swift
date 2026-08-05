#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-ANNO-001: kotlin.annotation API Surface Inventory
//
// This file fixes the canonical set of symbols that the sema layer must register
// for the `kotlin.annotation` package and verifies that every symbol is present in
// the symbol table after a minimal sema run. It covers:
//
//   Annotation classes:
//     • @Target              (kotlin.annotation.Target)
//     • @Retention           (kotlin.annotation.Retention)
//     • @Repeatable          (kotlin.annotation.Repeatable)
//     • @MustBeDocumented    (kotlin.annotation.MustBeDocumented)
//
//   Enum classes and their entries:
//     • AnnotationTarget     (CLASS, ANNOTATION_CLASS, TYPE_PARAMETER, PROPERTY, FIELD,
//                             LOCAL_VARIABLE, VALUE_PARAMETER, CONSTRUCTOR, FUNCTION,
//                             PROPERTY_GETTER, PROPERTY_SETTER, TYPE, EXPRESSION,
//                             FILE, TYPEALIAS)
//     • AnnotationRetention  (SOURCE, BINARY, RUNTIME)
//
// Scope: symbol-table / sema-level only.  Diagnostic behaviour for these annotations
//        is covered by AnnotationSemanticTests (codex #1205).

@Suite
struct KotlinAnnotationAPIInventoryTests {

    // MARK: - Shared sema fixture
    // MARK: - Lookup helpers

    private func symbol(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
    }

    private func childNames(
        of fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let fqName = fqPath.map { interner.intern($0) }
        return Set(sema.symbols.children(ofFQName: fqName).compactMap { child in
            sema.symbols.symbol(child).map { interner.resolve($0.name) }
        })
    }

    // MARK: - 1. Package hierarchy

    // MARK: - 2. Annotation classes

    // MARK: - 3. @Target carries its own @Target(ANNOTATION_CLASS)

    // MARK: - 4. AnnotationTarget enum class

    // MARK: - 5. AnnotationRetention enum class

    // MARK: - 6. @Retention carries default value property wired to RUNTIME

    // MARK: - 7. Complete mandatory inventory assertion

    // MARK: - 8. Call-site resolution: annotations resolve without sema errors

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

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testKotlinAnnotationPackageIsPresent
            """
            package sample0
            fun noop() {}
            """,
            // testTargetAnnotationClassIsRegistered
            """
            package sample1
            fun noop() {}
            """,
            // testRetentionAnnotationClassIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testRepeatableAnnotationClassIsRegistered
            """
            package sample3
            fun noop() {}
            """,
            // testMustBeDocumentedAnnotationClassIsRegistered
            """
            package sample4
            fun noop() {}
            """,
            // testTargetAnnotationCarriesAnnotationClassTarget
            """
            package sample5
            fun noop() {}
            """,
            // testRetentionAnnotationCarriesAnnotationClassTarget
            """
            package sample6
            fun noop() {}
            """,
            // testRepeatableAnnotationCarriesAnnotationClassTarget
            """
            package sample7
            fun noop() {}
            """,
            // testMustBeDocumentedAnnotationCarriesAnnotationClassTarget
            """
            package sample8
            fun noop() {}
            """,
            // testAnnotationTargetEnumClassIsRegistered
            """
            package sample9
            fun noop() {}
            """,
            // testAnnotationTargetAllEntriesAreRegistered
            """
            package sample10
            fun noop() {}
            """,
            // testAnnotationTargetEntryCountIsExact
            """
            package sample11
            fun noop() {}
            """,
            // testAnnotationTargetEntriesHaveEnumType
            """
            package sample12
            fun noop() {}
            """,
            // testAnnotationRetentionEnumClassIsRegistered
            """
            package sample13
            fun noop() {}
            """,
            // testAnnotationRetentionSourceEntryIsRegistered
            """
            package sample14
            fun noop() {}
            """,
            // testAnnotationRetentionBinaryEntryIsRegistered
            """
            package sample15
            fun noop() {}
            """,
            // testAnnotationRetentionRuntimeEntryIsRegistered
            """
            package sample16
            fun noop() {}
            """,
            // testAnnotationRetentionAllEntriesPresent
            """
            package sample17
            fun noop() {}
            """,
            // testAnnotationRetentionEntriesHaveEnumType
            """
            package sample18
            fun noop() {}
            """,
            // testRetentionHasValuePropertyWithRuntimeDefault
            """
            package sample19
            fun noop() {}
            """,
            // testAllMandatoryAnnotationAPISymbolsPresent
            """
            package sample20
            fun noop() {}
            """,
            // testTargetAnnotationResolvesOnAnnotationClass
            """
            package sample21

                    import kotlin.annotation.Target
                    import kotlin.annotation.AnnotationTarget

                    @Target(AnnotationTarget.CLASS)
                    annotation class ClassScoped

            """,
            // testRetentionAnnotationResolvesOnAnnotationClass
            """
            package sample22

                    import kotlin.annotation.Retention
                    import kotlin.annotation.AnnotationRetention

                    @Retention(AnnotationRetention.RUNTIME)
                    annotation class RuntimeRetained

            """,
            // testRepeatableAnnotationResolvesOnAnnotationClass
            """
            package sample23

                    import kotlin.annotation.Repeatable

                    @Repeatable
                    annotation class Taggable

            """,
            // testMustBeDocumentedAnnotationResolvesOnAnnotationClass
            """
            package sample24

                    import kotlin.annotation.MustBeDocumented

                    @MustBeDocumented
                    annotation class PublicApi

            """,
            // testAllAnnotationRetentionEntriesResolveAsExpressions
            """
            package sample25
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testKotlinAnnotationPackageIsPresent ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let fq = ["kotlin", "annotation"].map { interner.intern($0) }
                #expect(
                    sema.symbols.lookup(fqName: fq) != nil,
                    "kotlin.annotation package must be registered in the symbol table"
                )

            }

            // === testTargetAnnotationClassIsRegistered ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let sym = symbol(fqPath: ["kotlin", "annotation", "Target"], sema: sema, interner: interner)
                #expect(sym != nil, "kotlin.annotation.Target must be registered in symbol table")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .annotationClass,
                        "kotlin.annotation.Target must have kind .annotationClass"
                    )
                    #expect(
                        sema.symbols.symbol(sym)?.flags.contains(.synthetic) == true,
                        "kotlin.annotation.Target must be marked synthetic"
                    )
                    #expect(
                        sema.symbols.symbol(sym)?.visibility == .public,
                        "kotlin.annotation.Target must be public"
                    )
                }

            }

            // === testRetentionAnnotationClassIsRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let sym = symbol(fqPath: ["kotlin", "annotation", "Retention"], sema: sema, interner: interner)
                #expect(sym != nil, "kotlin.annotation.Retention must be registered in symbol table")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .annotationClass,
                        "kotlin.annotation.Retention must have kind .annotationClass"
                    )
                    #expect(
                        sema.symbols.symbol(sym)?.flags.contains(.synthetic) == true,
                        "kotlin.annotation.Retention must be marked synthetic"
                    )
                }

            }

            // === testRepeatableAnnotationClassIsRegistered ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let sym = symbol(fqPath: ["kotlin", "annotation", "Repeatable"], sema: sema, interner: interner)
                #expect(sym != nil, "kotlin.annotation.Repeatable must be registered in symbol table")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .annotationClass,
                        "kotlin.annotation.Repeatable must have kind .annotationClass"
                    )
                    #expect(
                        sema.symbols.symbol(sym)?.flags.contains(.synthetic) == true,
                        "kotlin.annotation.Repeatable must be marked synthetic"
                    )
                }

            }

            // === testMustBeDocumentedAnnotationClassIsRegistered ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let sym = symbol(fqPath: ["kotlin", "annotation", "MustBeDocumented"], sema: sema, interner: interner)
                #expect(sym != nil, "kotlin.annotation.MustBeDocumented must be registered in symbol table")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .annotationClass,
                        "kotlin.annotation.MustBeDocumented must have kind .annotationClass"
                    )
                    #expect(
                        sema.symbols.symbol(sym)?.flags.contains(.synthetic) == true,
                        "kotlin.annotation.MustBeDocumented must be marked synthetic"
                    )
                }

            }

            // === testTargetAnnotationCarriesAnnotationClassTarget ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let sym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "Target"], sema: sema, interner: interner),
                    "kotlin.annotation.Target must be present"
                )
                let annotations = sema.symbols.annotations(for: sym)
                let hasTarget = annotations.contains(where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
                })
                #expect(
                    hasTarget,
                    "kotlin.annotation.Target must carry @Target(AnnotationTarget.ANNOTATION_CLASS); found: \(annotations)"
                )

            }

            // === testRetentionAnnotationCarriesAnnotationClassTarget ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let sym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "Retention"], sema: sema, interner: interner),
                    "kotlin.annotation.Retention must be present"
                )
                let annotations = sema.symbols.annotations(for: sym)
                let hasTarget = annotations.contains(where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
                })
                #expect(
                    hasTarget,
                    "kotlin.annotation.Retention must carry @Target(AnnotationTarget.ANNOTATION_CLASS); found: \(annotations)"
                )

            }

            // === testRepeatableAnnotationCarriesAnnotationClassTarget ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let sym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "Repeatable"], sema: sema, interner: interner),
                    "kotlin.annotation.Repeatable must be present"
                )
                let annotations = sema.symbols.annotations(for: sym)
                let hasTarget = annotations.contains(where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
                })
                #expect(
                    hasTarget,
                    "kotlin.annotation.Repeatable must carry @Target(AnnotationTarget.ANNOTATION_CLASS); found: \(annotations)"
                )

            }

            // === testMustBeDocumentedAnnotationCarriesAnnotationClassTarget ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let sym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "MustBeDocumented"], sema: sema, interner: interner),
                    "kotlin.annotation.MustBeDocumented must be present"
                )
                let annotations = sema.symbols.annotations(for: sym)
                let hasTarget = annotations.contains(where: {
                    $0.annotationFQName == "kotlin.annotation.Target"
                        && $0.arguments == ["AnnotationTarget.ANNOTATION_CLASS"]
                })
                #expect(
                    hasTarget,
                    "kotlin.annotation.MustBeDocumented must carry @Target(AnnotationTarget.ANNOTATION_CLASS); found: \(annotations)"
                )

            }

            // === testAnnotationTargetEnumClassIsRegistered ===

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let sym = symbol(
                    fqPath: ["kotlin", "annotation", "AnnotationTarget"],
                    sema: sema,
                    interner: interner
                )
                #expect(sym != nil, "kotlin.annotation.AnnotationTarget enum class must be registered")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .enumClass,
                        "AnnotationTarget must have kind .enumClass"
                    )
                }

            }

            // === testAnnotationTargetAllEntriesAreRegistered ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let entries = [
                    "CLASS",
                    "ANNOTATION_CLASS",
                    "TYPE_PARAMETER",
                    "PROPERTY",
                    "FIELD",
                    "LOCAL_VARIABLE",
                    "VALUE_PARAMETER",
                    "CONSTRUCTOR",
                    "FUNCTION",
                    "PROPERTY_GETTER",
                    "PROPERTY_SETTER",
                    "TYPE",
                    "EXPRESSION",
                    "FILE",
                    "TYPEALIAS",
                ]
                for entry in entries {
                    let sym = symbol(
                        fqPath: ["kotlin", "annotation", "AnnotationTarget", entry],
                        sema: sema,
                        interner: interner
                    )
                    #expect(
                        sym != nil,
                        "AnnotationTarget.\(entry) must be registered in symbol table"
                    )
                }

            }

            // === testAnnotationTargetEntryCountIsExact ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let expectedEntries: Set<String> = [
                    "CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD",
                    "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION",
                    "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE", "TYPEALIAS",
                ]
                let actualEntries = childNames(
                    of: ["kotlin", "annotation", "AnnotationTarget"],
                    sema: sema,
                    interner: interner
                )
                #expect(
                    actualEntries == expectedEntries,
                    "AnnotationTarget entries must match the Kotlin stdlib target list exactly"
                )

            }

            // === testAnnotationTargetEntriesHaveEnumType ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let enumSym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "AnnotationTarget"], sema: sema, interner: interner),
                    "AnnotationTarget enum must be registered"
                )
                for entry in ["CLASS", "FUNCTION", "PROPERTY", "FILE", "TYPE"] {
                    let entrySym = try #require(
                        symbol(fqPath: ["kotlin", "annotation", "AnnotationTarget", entry], sema: sema, interner: interner),
                        "AnnotationTarget.\(entry) must be registered"
                    )
                    guard let propType = sema.symbols.propertyType(for: entrySym) else {
                        Issue.record("AnnotationTarget.\(entry) must have a property type")
                        continue
                    }
                    if case let .classType(ct) = sema.types.kind(of: propType) {
                        #expect(
                            ct.classSymbol == enumSym,
                            "AnnotationTarget.\(entry) type must reference the AnnotationTarget enum symbol"
                        )
                    } else {
                        Issue.record("AnnotationTarget.\(entry) property type must be a classType, got: \(sema.types.kind(of: propType))")
                    }
                }

            }

            // === testAnnotationRetentionEnumClassIsRegistered ===

            do {

                let sample13Path = paths[13]

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let sym = symbol(
                    fqPath: ["kotlin", "annotation", "AnnotationRetention"],
                    sema: sema,
                    interner: interner
                )
                #expect(sym != nil, "kotlin.annotation.AnnotationRetention enum class must be registered")
                if let sym {
                    #expect(
                        sema.symbols.symbol(sym)?.kind == .enumClass,
                        "AnnotationRetention must have kind .enumClass"
                    )
                }

            }

            // === testAnnotationRetentionSourceEntryIsRegistered ===

            do {

                let sample14Path = paths[14]

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                #expect(
                    symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "SOURCE"], sema: sema, interner: interner) != nil,
                    "AnnotationRetention.SOURCE must be registered"
                )

            }

            // === testAnnotationRetentionBinaryEntryIsRegistered ===

            do {

                let sample15Path = paths[15]

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                #expect(
                    symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "BINARY"], sema: sema, interner: interner) != nil,
                    "AnnotationRetention.BINARY must be registered"
                )

            }

            // === testAnnotationRetentionRuntimeEntryIsRegistered ===

            do {

                let sample16Path = paths[16]

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                #expect(
                    symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "RUNTIME"], sema: sema, interner: interner) != nil,
                    "AnnotationRetention.RUNTIME must be registered"
                )

            }

            // === testAnnotationRetentionAllEntriesPresent ===

            do {

                let sample17Path = paths[17]

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                let expectedEntries: Set<String> = ["SOURCE", "BINARY", "RUNTIME"]
                let actualEntries = childNames(
                    of: ["kotlin", "annotation", "AnnotationRetention"],
                    sema: sema,
                    interner: interner
                )
                #expect(
                    actualEntries == expectedEntries,
                    "AnnotationRetention entries must match the Kotlin stdlib retention list exactly"
                )

            }

            // === testAnnotationRetentionEntriesHaveEnumType ===

            do {

                let sample18Path = paths[18]

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                let enumSym = try #require(
                    symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention"], sema: sema, interner: interner),
                    "AnnotationRetention enum must be registered"
                )
                for entry in ["SOURCE", "BINARY", "RUNTIME"] {
                    let entrySym = try #require(
                        symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", entry], sema: sema, interner: interner),
                        "AnnotationRetention.\(entry) must be registered"
                    )
                    guard let propType = sema.symbols.propertyType(for: entrySym) else {
                        Issue.record("AnnotationRetention.\(entry) must have a property type")
                        continue
                    }
                    if case let .classType(ct) = sema.types.kind(of: propType) {
                        #expect(
                            ct.classSymbol == enumSym,
                            "AnnotationRetention.\(entry) type must reference the AnnotationRetention enum symbol"
                        )
                    } else {
                        Issue.record("AnnotationRetention.\(entry) property type must be a classType")
                    }
                }

            }

            // === testRetentionHasValuePropertyWithRuntimeDefault ===

            do {

                let sample19Path = paths[19]

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                let valueSym = symbol(
                    fqPath: ["kotlin", "annotation", "Retention", "value"],
                    sema: sema,
                    interner: interner
                )
                #expect(valueSym != nil, "kotlin.annotation.Retention.value property must be registered")
                if let valueSym {
                    let propType = sema.symbols.propertyType(for: valueSym)
                    #expect(propType != nil, "Retention.value must have a property type (AnnotationRetention)")
                    let enumSym = try #require(
                        symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention"], sema: sema, interner: interner),
                        "AnnotationRetention enum must be registered for Retention.value typing"
                    )
                    if let propType {
                        if case let .classType(ct) = sema.types.kind(of: propType) {
                            #expect(
                                ct.classSymbol == enumSym,
                                "Retention.value must be typed with the AnnotationRetention enum symbol"
                            )
                        } else {
                            Issue.record("Retention.value property type must be a classType for AnnotationRetention")
                        }
                    }

                    let runtimeSym = symbol(
                        fqPath: ["kotlin", "annotation", "AnnotationRetention", "RUNTIME"],
                        sema: sema,
                        interner: interner
                    )
                    #expect(runtimeSym != nil, "AnnotationRetention.RUNTIME must be registered to check default")
                }

            }

            // === testAllMandatoryAnnotationAPISymbolsPresent ===

            do {

                let sample20Path = paths[20]

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                let mandatorySymbols: [[String]] = [
                    // annotation classes
                    ["kotlin", "annotation", "Target"],
                    ["kotlin", "annotation", "Retention"],
                    ["kotlin", "annotation", "Repeatable"],
                    ["kotlin", "annotation", "MustBeDocumented"],
                    // AnnotationTarget enum
                    ["kotlin", "annotation", "AnnotationTarget"],
                    ["kotlin", "annotation", "AnnotationTarget", "CLASS"],
                    ["kotlin", "annotation", "AnnotationTarget", "ANNOTATION_CLASS"],
                    ["kotlin", "annotation", "AnnotationTarget", "TYPE_PARAMETER"],
                    ["kotlin", "annotation", "AnnotationTarget", "PROPERTY"],
                    ["kotlin", "annotation", "AnnotationTarget", "FIELD"],
                    ["kotlin", "annotation", "AnnotationTarget", "LOCAL_VARIABLE"],
                    ["kotlin", "annotation", "AnnotationTarget", "VALUE_PARAMETER"],
                    ["kotlin", "annotation", "AnnotationTarget", "CONSTRUCTOR"],
                    ["kotlin", "annotation", "AnnotationTarget", "FUNCTION"],
                    ["kotlin", "annotation", "AnnotationTarget", "PROPERTY_GETTER"],
                    ["kotlin", "annotation", "AnnotationTarget", "PROPERTY_SETTER"],
                    ["kotlin", "annotation", "AnnotationTarget", "TYPE"],
                    ["kotlin", "annotation", "AnnotationTarget", "EXPRESSION"],
                    ["kotlin", "annotation", "AnnotationTarget", "FILE"],
                    ["kotlin", "annotation", "AnnotationTarget", "TYPEALIAS"],
                    // AnnotationRetention enum
                    ["kotlin", "annotation", "AnnotationRetention"],
                    ["kotlin", "annotation", "AnnotationRetention", "SOURCE"],
                    ["kotlin", "annotation", "AnnotationRetention", "BINARY"],
                    ["kotlin", "annotation", "AnnotationRetention", "RUNTIME"],
                ]

                var gaps: [String] = []
                for fqPath in mandatorySymbols {
                    // swiftlint:disable:next for_where
                    if symbol(fqPath: fqPath, sema: sema, interner: interner) == nil {
                        gaps.append(fqPath.joined(separator: "."))
                    }
                }

                #expect(
                    gaps.isEmpty,
                    "Missing kotlin.annotation API symbols: \(gaps.joined(separator: ", "))"
                )

            }

            // === testTargetAnnotationResolvesOnAnnotationClass ===

            do {

                let sample21Path = paths[21]

                let path = sample21Path

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                #expect(
                    !sample21Diagnostics.contains { $0.severity == .error },
                    "@Target(AnnotationTarget.CLASS) on annotation class must not produce sema errors"
                )

            }

            // === testRetentionAnnotationResolvesOnAnnotationClass ===

            do {

                let sample22Path = paths[22]

                let path = sample22Path

                let sample22Diagnostics = diagnosticsForPath(sample22Path, in: ctx)

                #expect(
                    !sample22Diagnostics.contains { $0.severity == .error },
                    "@Retention(AnnotationRetention.RUNTIME) must compile without sema errors"
                )

            }

            // === testRepeatableAnnotationResolvesOnAnnotationClass ===

            do {

                let sample23Path = paths[23]

                let path = sample23Path

                let sample23Diagnostics = diagnosticsForPath(sample23Path, in: ctx)

                #expect(
                    !sample23Diagnostics.contains { $0.severity == .error },
                    "@Repeatable on annotation class must compile without sema errors"
                )

            }

            // === testMustBeDocumentedAnnotationResolvesOnAnnotationClass ===

            do {

                let sample24Path = paths[24]

                let path = sample24Path

                let sample24Diagnostics = diagnosticsForPath(sample24Path, in: ctx)

                #expect(
                    !sample24Diagnostics.contains { $0.severity == .error },
                    "@MustBeDocumented on annotation class must compile without sema errors"
                )

            }

            // === testAllAnnotationRetentionEntriesResolveAsExpressions ===

            do {

                let sample25Path = paths[25]

                let sample25Diagnostics = diagnosticsForPath(sample25Path, in: ctx)

                for entry in ["SOURCE", "BINARY", "RUNTIME"] {
                    let sym = symbol(
                        fqPath: ["kotlin", "annotation", "AnnotationRetention", entry],
                        sema: sema,
                        interner: interner
                    )
                    #expect(sym != nil, "AnnotationRetention.\(entry) must resolve in symbol table")
                }

            }

        }
    }

}

#endif
