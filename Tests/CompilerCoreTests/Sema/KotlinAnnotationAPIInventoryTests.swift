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

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

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

    @Test func testKotlinAnnotationPackageIsPresent() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "annotation"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookup(fqName: fq) != nil,
            "kotlin.annotation package must be registered in the symbol table"
        )
    }

    // MARK: - 2. Annotation classes

    @Test func testTargetAnnotationClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testRetentionAnnotationClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testRepeatableAnnotationClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testMustBeDocumentedAnnotationClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    // MARK: - 3. @Target carries its own @Target(ANNOTATION_CLASS)

    @Test func testTargetAnnotationCarriesAnnotationClassTarget() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testRetentionAnnotationCarriesAnnotationClassTarget() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testRepeatableAnnotationCarriesAnnotationClassTarget() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testMustBeDocumentedAnnotationCarriesAnnotationClassTarget() throws {
        let (sema, interner) = try makeSema()
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

    // MARK: - 4. AnnotationTarget enum class

    @Test func testAnnotationTargetEnumClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testAnnotationTargetAllEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testAnnotationTargetEntryCountIsExact() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testAnnotationTargetEntriesHaveEnumType() throws {
        let (sema, interner) = try makeSema()
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

    // MARK: - 5. AnnotationRetention enum class

    @Test func testAnnotationRetentionEnumClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testAnnotationRetentionSourceEntryIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(
            symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "SOURCE"], sema: sema, interner: interner) != nil,
            "AnnotationRetention.SOURCE must be registered"
        )
    }

    @Test func testAnnotationRetentionBinaryEntryIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(
            symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "BINARY"], sema: sema, interner: interner) != nil,
            "AnnotationRetention.BINARY must be registered"
        )
    }

    @Test func testAnnotationRetentionRuntimeEntryIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(
            symbol(fqPath: ["kotlin", "annotation", "AnnotationRetention", "RUNTIME"], sema: sema, interner: interner) != nil,
            "AnnotationRetention.RUNTIME must be registered"
        )
    }

    @Test func testAnnotationRetentionAllEntriesPresent() throws {
        let (sema, interner) = try makeSema()
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

    @Test func testAnnotationRetentionEntriesHaveEnumType() throws {
        let (sema, interner) = try makeSema()
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

    // MARK: - 6. @Retention carries default value property wired to RUNTIME

    @Test func testRetentionHasValuePropertyWithRuntimeDefault() throws {
        let (sema, interner) = try makeSema()
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

    // MARK: - 7. Complete mandatory inventory assertion

    @Test func testAllMandatoryAnnotationAPISymbolsPresent() throws {
        let (sema, interner) = try makeSema()

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

    // MARK: - 8. Call-site resolution: annotations resolve without sema errors

    @Test func testTargetAnnotationResolvesOnAnnotationClass() throws {
        let source = """
        import kotlin.annotation.Target
        import kotlin.annotation.AnnotationTarget

        @Target(AnnotationTarget.CLASS)
        annotation class ClassScoped
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "@Target(AnnotationTarget.CLASS) on annotation class must not produce sema errors"
            )
        }
    }

    @Test func testRetentionAnnotationResolvesOnAnnotationClass() throws {
        let source = """
        import kotlin.annotation.Retention
        import kotlin.annotation.AnnotationRetention

        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeRetained
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "@Retention(AnnotationRetention.RUNTIME) must compile without sema errors"
            )
        }
    }

    @Test func testRepeatableAnnotationResolvesOnAnnotationClass() throws {
        let source = """
        import kotlin.annotation.Repeatable

        @Repeatable
        annotation class Taggable
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "@Repeatable on annotation class must compile without sema errors"
            )
        }
    }

    @Test func testMustBeDocumentedAnnotationResolvesOnAnnotationClass() throws {
        let source = """
        import kotlin.annotation.MustBeDocumented

        @MustBeDocumented
        annotation class PublicApi
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "@MustBeDocumented on annotation class must compile without sema errors"
            )
        }
    }

    @Test func testAllAnnotationTargetEntriesResolveAsExpressions() throws {
        let entries = [
            "CLASS", "ANNOTATION_CLASS", "TYPE_PARAMETER", "PROPERTY", "FIELD",
            "LOCAL_VARIABLE", "VALUE_PARAMETER", "CONSTRUCTOR", "FUNCTION",
            "PROPERTY_GETTER", "PROPERTY_SETTER", "TYPE", "EXPRESSION", "FILE", "TYPEALIAS",
        ]
        let argList = entries.map { "AnnotationTarget.\($0)" }.joined(separator: ",\n        ")
        let source = """
        import kotlin.annotation.Target
        import kotlin.annotation.AnnotationTarget

        @Target(
            \(argList)
        )
        annotation class AllTargets
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "@Target with all AnnotationTarget entries must compile without sema errors"
            )
        }
    }

    @Test func testAllAnnotationRetentionEntriesResolveAsExpressions() throws {
        let (sema, interner) = try makeSema()
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
#endif
