#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-EXPERIMENTAL-ABI-001: Synthetic experimental opt-in marker stubs
//
// Verifies that the Kotlin stdlib experimental annotation classes discovered
// missing in PR #1231 are now synthesised correctly:
//
//   • ExperimentalUnsignedTypes  — kotlin          — severity ERROR
//   • ExperimentalVersionOverloading — kotlin       — severity ERROR
//   • ExperimentalContextParameters — kotlin        — severity ERROR
//   • ExperimentalUuidApi        — kotlin.uuid      — severity ERROR
//   • ExperimentalEncodingApi    — kotlin.io.encoding — severity ERROR
//   • ExperimentalWasmInterop    — kotlin.wasm      — severity WARNING
//   • ExperimentalMultiplatform  — kotlin           — severity ERROR
//   • ExperimentalSubclassOptIn  — kotlin           — severity WARNING
//   • ExperimentalAssociatedObjects — kotlin.reflect — severity ERROR
//
// Each test group checks:
//   1. The annotation class symbol is present in the symbol table.
//   2. Its kind is .annotationClass.
//   3. It carries @RequiresOptIn.
//   4. The @RequiresOptIn argument encodes the correct severity level.

@Suite
struct ExperimentalMarkerStubTests {
    private struct ExperimentalPackageMarker: Hashable {
        let name: String
        let todo: String?
    }

    private static let implementedExperimentalPackageMarkers: Set<ExperimentalPackageMarker> = [
        ExperimentalPackageMarker(name: "ExperimentalNativeApi", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCEnum", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCName", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalObjCRefinement", todo: nil),
        ExperimentalPackageMarker(name: "ExperimentalTypeInference", todo: nil),
        ExperimentalPackageMarker(name: "ExpectRefinement", todo: nil),
    ]

    private static let knownGapExperimentalPackageMarkers: Set<ExperimentalPackageMarker> = []

    private static let optInExperimentalPackageMarkerNames: [String] = [
        "ExperimentalNativeApi",
        "ExperimentalObjCEnum",
        "ExperimentalObjCName",
        "ExperimentalObjCRefinement",
    ]

    // MARK: - Shared fixture

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

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    private func runSemaCollectingDiagnostics(_ sources: [String]) -> CompilationContext {
        let ctx = makeContextFromSources(sources)
        do {
            try runSema(ctx)
        } catch {
            // Diagnostics are inspected per-test.
        }
        return ctx
    }

    // MARK: - Helpers

    private func lookupSymbol(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookup(fqName: interned)
    }

    private func assertIsAnnotationClass(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) {
        guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner),
              let info = sema.symbols.symbol(sym)
        else {
            Issue.record("\(fqPath.joined(separator: ".")) not found in symbol table")
            return
        }
        #expect(info.kind == .annotationClass, "\(fqPath.last ?? "") must have kind=annotationClass")
    }

    private func assertHasRequiresOptIn(
        fqPath: [String],
        expectedSeverity: String,
        sema: SemaModule,
        interner: StringInterner
    ) {
        guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner) else {
            Issue.record("\(fqPath.joined(separator: ".")) not found in symbol table")
            return
        }
        let annotations = sema.symbols.annotations(for: sym)
        guard let requiresOptIn = annotations.first(where: { $0.annotationFQName == "kotlin.RequiresOptIn" }) else {
            Issue.record("\(fqPath.last ?? "") must carry @RequiresOptIn annotation")
            return
        }
        let hasSeverity = requiresOptIn.arguments.contains { $0.contains(expectedSeverity) }
        #expect(
            hasSeverity,
            "\(fqPath.last ?? "") @RequiresOptIn must declare severity=\(expectedSeverity); got \(requiresOptIn.arguments)"
        )
    }

    // MARK: - ExperimentalUnsignedTypes (kotlin, ERROR)

    @Test func testExperimentalUnsignedTypesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalUnsignedTypes"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.ExperimentalUnsignedTypes must be registered in the symbol table")
    }

    @Test func testExperimentalUnsignedTypesIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalUnsignedTypes"], sema: sema, interner: interner)
    }

    @Test func testExperimentalUnsignedTypesHasRequiresOptIn() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalUnsignedTypes"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalVersionOverloading (kotlin, ERROR)

    @Test func testExperimentalVersionOverloadingIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalVersionOverloading"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.ExperimentalVersionOverloading must be registered in the symbol table")
    }

    @Test func testExperimentalVersionOverloadingIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalVersionOverloading"], sema: sema, interner: interner)
    }

    @Test func testExperimentalVersionOverloadingHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalVersionOverloading"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalContextParameters (kotlin, ERROR)

    @Test func testExperimentalContextParametersIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.ExperimentalContextParameters must be registered in the symbol table")
    }

    @Test func testExperimentalContextParametersIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
    }

    @Test func testExperimentalContextParametersHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalContextParameters"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalContextParametersRequiresOptInMessageMentionsContextParameters() throws {
        let (sema, interner) = try makeSema()
        let sym = try #require(
            lookupSymbol(fqPath: ["kotlin", "ExperimentalContextParameters"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        let requiresOptIn = try #require(annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" })
        let mentionsContextParams = requiresOptIn.arguments.contains { $0.contains("context parameters") }
        #expect(
            mentionsContextParams,
            "Expected ExperimentalContextParameters @RequiresOptIn message to mention context parameters, got: \(requiresOptIn.arguments)"
        )
    }

    // MARK: - ExperimentalUuidApi (kotlin.uuid, ERROR)

    @Test func testExperimentalUuidApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.uuid.ExperimentalUuidApi must be registered in the symbol table")
    }

    @Test func testExperimentalUuidApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"], sema: sema, interner: interner)
    }

    @Test func testExperimentalUuidApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalEncodingApi (kotlin.io.encoding, ERROR)

    @Test func testExperimentalEncodingApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            sema: sema,
            interner: interner
        )
        #expect(sym != nil, "kotlin.io.encoding.ExperimentalEncodingApi must be registered in the symbol table")
    }

    @Test func testExperimentalEncodingApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalEncodingApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    @Test func testKotlinIoEncodingPackageIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "io", "encoding"].map { interner.intern($0) }
        #expect(
            sema.symbols.lookup(fqName: fq) != nil,
            "kotlin.io.encoding package must be present in the symbol table after sema"
        )
    }

    // MARK: - ExperimentalWasmInterop (kotlin.wasm, WARNING)

    @Test func testExperimentalWasmInteropIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.wasm.ExperimentalWasmInterop must be registered in the symbol table")
    }

    @Test func testExperimentalWasmInteropIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"], sema: sema, interner: interner)
    }

    @Test func testExperimentalWasmInteropHasRequiresOptInWithWarningSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "wasm", "ExperimentalWasmInterop"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalPathApi (kotlin.io.path, ERROR)

    @Test func testExperimentalPathApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            sema: sema,
            interner: interner
        )
        #expect(sym != nil, "kotlin.io.path.ExperimentalPathApi must be registered in the symbol table")
    }

    @Test func testExperimentalPathApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalPathApiHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalPathApiHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let sym = try #require(
            lookupSymbol(fqPath: ["kotlin", "io", "path", "ExperimentalPathApi"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        let hasTarget = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Target"
                && $0.arguments == [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
        }
        #expect(
            hasTarget,
            "ExperimentalPathApi must carry the official @Target list, got \(annotations)"
        )
    }

    // MARK: - ExperimentalAssociatedObjects (kotlin.reflect, ERROR)

    @Test func testExperimentalAssociatedObjectsIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            sema: sema,
            interner: interner
        )
        #expect(sym != nil, "kotlin.reflect.ExperimentalAssociatedObjects must be registered in the symbol table")
    }

    @Test func testExperimentalAssociatedObjectsIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalAssociatedObjectsHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalAssociatedObjectsHasBinaryRetention() throws {
        let (sema, interner) = try makeSema()
        let sym = try #require(
            lookupSymbol(fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: sym)
        let hasRetention = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments.contains("AnnotationRetention.BINARY")
        }
        #expect(
            hasRetention,
            "Expected ExperimentalAssociatedObjects to carry @Retention(BINARY), got: \(annotations)"
        )
    }

    // MARK: - ExperimentalMultiplatform (kotlin, ERROR)

    @Test func testExperimentalMultiplatformIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalMultiplatform"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.ExperimentalMultiplatform must be registered in the symbol table")
    }

    @Test func testExperimentalMultiplatformIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalMultiplatform"], sema: sema, interner: interner)
    }

    @Test func testExperimentalMultiplatformHasRequiresOptInWithErrorSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalMultiplatform"],
            expectedSeverity: "ERROR",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - ExperimentalSubclassOptIn (kotlin, WARNING)

    @Test func testExperimentalSubclassOptInIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "ExperimentalSubclassOptIn"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.ExperimentalSubclassOptIn must be registered in the symbol table")
    }

    @Test func testExperimentalSubclassOptInIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "ExperimentalSubclassOptIn"], sema: sema, interner: interner)
    }

    @Test func testExperimentalSubclassOptInHasRequiresOptInWithWarningSeverity() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "ExperimentalSubclassOptIn"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    // MARK: - Severity cross-check: ERROR vs WARNING are distinct

    @Test func testErrorAndWarningSeveritiesAreDistinctAcrossMarkers() throws {
        let (sema, interner) = try makeSema()

        func severity(fqPath: [String]) -> String? {
            guard let sym = lookupSymbol(fqPath: fqPath, sema: sema, interner: interner) else {
                return nil
            }
            let annotations = sema.symbols.annotations(for: sym)
            guard let req = annotations.first(where: { $0.annotationFQName == "kotlin.RequiresOptIn" }) else {
                return nil
            }
            if req.arguments.contains(where: { $0.contains("ERROR") }) { return "ERROR" }
            if req.arguments.contains(where: { $0.contains("WARNING") }) { return "WARNING" }
            return nil
        }

        #expect(severity(fqPath: ["kotlin", "ExperimentalUnsignedTypes"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "ExperimentalVersionOverloading"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "ExperimentalContextParameters"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "uuid", "ExperimentalUuidApi"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "io", "encoding", "ExperimentalEncodingApi"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "reflect", "ExperimentalAssociatedObjects"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "ExperimentalMultiplatform"]) == "ERROR")
        #expect(severity(fqPath: ["kotlin", "ExperimentalSubclassOptIn"]) == "WARNING")
    }

    // MARK: - kotlin.experimental marker inventory

    @Test func testKotlinExperimentalMarkerInventoryHasExpectedShape() {
        let targetMarkers = Self.implementedExperimentalPackageMarkers.union(Self.knownGapExperimentalPackageMarkers)
        let targetNames = Set(targetMarkers.map(\.name))

        #expect(targetMarkers.count == targetNames.count)
        #expect(targetMarkers.count == 6)
        #expect(Self.implementedExperimentalPackageMarkers.count == 6)
        #expect(Self.knownGapExperimentalPackageMarkers.count == 0)
    }

    @Test func testImplementedKotlinExperimentalMarkersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.implementedExperimentalPackageMarkers {
            let symbol = try #require(
                lookupSymbol(fqPath: ["kotlin", "experimental", marker.name], sema: sema, interner: interner),
                "kotlin.experimental.\(marker.name) should be registered"
            )
            #expect(
                sema.symbols.symbol(symbol)?.kind == .annotationClass,
                "kotlin.experimental.\(marker.name) should be an annotation class"
            )
        }
    }

    @Test func testKnownGapKotlinExperimentalMarkersRemainAbsentUntilTheirTodoIsImplemented() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.knownGapExperimentalPackageMarkers {
            let symbol = lookupSymbol(fqPath: ["kotlin", "experimental", marker.name], sema: sema, interner: interner)
            #expect(
                symbol == nil,
                "kotlin.experimental.\(marker.name) is tracked by \(marker.todo ?? "unknown TODO") and should update this inventory when implemented"
            )
        }
    }

    @Test func testKnownGapKotlinExperimentalMarkerTodosAreScoped() {
        let todos = Set(Self.knownGapExperimentalPackageMarkers.compactMap(\.todo))
        #expect(todos == Set<String>())
    }

    @Test func testExpectRefinementCarriesClassTargetAndExperimentalMultiplatformMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "experimental", "ExpectRefinement"], sema: sema, interner: interner),
            "kotlin.experimental.ExpectRefinement should be registered"
        )
        let annotations = sema.symbols.annotations(for: symbol)

        let hasTarget = annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Target"
                && $0.arguments == ["AnnotationTarget.CLASS"]
        }
        #expect(
            hasTarget,
            "ExpectRefinement should carry @Target(AnnotationTarget.CLASS), got \(annotations)"
        )
        let hasExperimentalMultiplatform = annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" }
        #expect(
            hasExperimentalMultiplatform,
            "ExpectRefinement should carry @ExperimentalMultiplatform, got \(annotations)"
        )
    }

    @Test func testExpectRefinementMetadataIsExposedOnExpectDeclaration() throws {
        let sources = [
            """
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)

            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class Refined
            """,
            """
            package sample.exp

            actual class Refined
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected expect/actual refined class to compile cleanly, got \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let fqName = ["sample", "exp", "Refined"].map { ctx.interner.intern($0) }
        let refinedSymbol = try #require(
            sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                sema.symbols.symbol(symbolID)?.flags.contains(.expectDeclaration) == true
            },
            "Expected expect Refined symbol to be registered"
        )
        let annotations = sema.symbols.annotations(for: refinedSymbol)
        let hasAnnotation = annotations.contains {
            $0.annotationFQName == "kotlin.experimental.ExpectRefinement"
                || $0.annotationFQName == "ExpectRefinement"
        }
        #expect(
            hasAnnotation,
            "Expected @ExpectRefinement metadata on expect declaration, got \(annotations)"
        )
    }

    @Test func testExpectRefinementUseRequiresExperimentalMultiplatformOptIn() {
        let sources = [
            """
            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class NeedsOptIn

            fun echo(value: NeedsOptIn): NeedsOptIn = value
            """,
            """
            package sample.exp

            actual class NeedsOptIn
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        let hasDiagnostic = diagnostics.contains {
            $0.severity == .error && $0.message.contains("kotlin.ExperimentalMultiplatform")
        }
        #expect(
            hasDiagnostic,
            "Expected ExpectRefinement usage to require ExperimentalMultiplatform opt-in, got \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testExpectRefinementAcceptsExperimentalMultiplatformOptIn() {
        let sources = [
            """
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)

            package sample.exp

            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class RefinedWithOptIn

            fun echo(value: RefinedWithOptIn): RefinedWithOptIn = value
            """,
            """
            package sample.exp

            actual class RefinedWithOptIn
            """,
        ]

        let ctx = runSemaCollectingDiagnostics(sources)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(
            diagnostics.isEmpty,
            "Expected @OptIn(kotlin.ExperimentalMultiplatform::class) to suppress ExpectRefinement diagnostics, got \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test func testExpectRefinementRejectsFunctionTarget() {
        let source = """
        @file:OptIn(kotlin.ExperimentalMultiplatform::class)

        import kotlin.experimental.ExpectRefinement

        @ExpectRefinement
        fun invalidRefinementTarget() {}
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
        #expect(
            diagnostics.count == 1,
            "Expected ExpectRefinement to reject function target, got \(ctx.diagnostics.diagnostics)"
        )
        let allErrors = diagnostics.allSatisfy { $0.severity == .error }
        #expect(
            allErrors,
            "ExpectRefinement target diagnostics should be errors"
        )
    }

    @Test func testKotlinExperimentalOptInMarkersCarryRequiresOptInError() throws {
        let (sema, interner) = try makeSema()

        for marker in Self.optInExperimentalPackageMarkerNames {
            let symbol = try #require(
                lookupSymbol(fqPath: ["kotlin", "experimental", marker], sema: sema, interner: interner),
                "kotlin.experimental.\(marker) should be registered"
            )
            let annotations = sema.symbols.annotations(for: symbol)
            let hasRequiresOptIn = annotations.contains {
                $0.annotationFQName == "kotlin.RequiresOptIn"
                    && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
            }
            #expect(
                hasRequiresOptIn,
                "kotlin.experimental.\(marker) should carry @RequiresOptIn(ERROR), got \(annotations)"
            )
        }
    }

    @Test func testKotlinExperimentalOptInMarkersEmitDiagnosticsOnUse() {
        for marker in Self.optInExperimentalPackageMarkerNames {
            let source = """
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """

            let ctx = runSemaCollectingDiagnostics(source)
            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            let hasError = diagnostics.contains { $0.severity == .error }
            #expect(
                hasError,
                "Expected \(marker) use to emit an opt-in error, got \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test func testKotlinExperimentalOptInMarkersAcceptExplicitOptIn() {
        for marker in Self.optInExperimentalPackageMarkerNames {
            let source = """
            @file:OptIn(kotlin.experimental.\(marker)::class)
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """

            let ctx = runSemaCollectingDiagnostics(source)
            let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
            #expect(
                diagnostics.isEmpty,
                "Expected @OptIn(\(marker)::class) to suppress opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    // MARK: - ExperimentalJsCollectionsApi (kotlin.js, WARNING)

    @Test func testExperimentalJsCollectionsApiIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.js.ExperimentalJsCollectionsApi must be registered in the symbol table")
    }

    @Test func testExperimentalJsCollectionsApiIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
    }

    @Test func testExperimentalJsCollectionsApiHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsCollectionsApiHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsCollectionsApi"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsCollectionsApi should carry explicit @Target metadata"
        )
        #expect(
            Set(target.arguments) == Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.FUNCTION",
            ])
        )
    }

    // MARK: - ExperimentalJsExport (kotlin.js, WARNING)

    @Test func testExperimentalJsExportIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.js.ExperimentalJsExport must be registered in the symbol table")
    }

    @Test func testExperimentalJsExportIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
    }

    @Test func testExperimentalJsExportHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsExport"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsExportDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsExport"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        let hasTarget = annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" }
        #expect(
            !hasTarget,
            "ExperimentalJsExport should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    @Test func testExperimentalJsExportEmitsWarningOnUse() {
        let source = """
        import kotlin.js.ExperimentalJsExport

        @ExperimentalJsExport
        @Target(AnnotationTarget.FUNCTION)
        annotation class UsesExperimentalJsExport

        @UsesExperimentalJsExport
        fun exported(): Int = 1

        fun callExported(): Int = exported()
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        let hasWarning = diagnostics.contains { $0.severity == .warning }
        #expect(
            hasWarning,
            "Expected ExperimentalJsExport use to emit an opt-in warning, got \(ctx.diagnostics.diagnostics)"
        )
    }

    // MARK: - ExperimentalJsFileName (kotlin.js, WARNING)

    @Test func testExperimentalJsFileNameIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.js.ExperimentalJsFileName must be registered in the symbol table")
    }

    @Test func testExperimentalJsFileNameIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
    }

    @Test func testExperimentalJsFileNameHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsFileName"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsFileNameDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsFileName"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        let hasTarget = annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" }
        #expect(
            !hasTarget,
            "ExperimentalJsFileName should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    // MARK: - ExperimentalJsReflectionCreateInstance (kotlin.js, WARNING)

    @Test func testExperimentalJsReflectionCreateInstanceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            sema: sema,
            interner: interner
        )
        #expect(sym != nil, "kotlin.js.ExperimentalJsReflectionCreateInstance must be registered in the symbol table")
    }

    @Test func testExperimentalJsReflectionCreateInstanceIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsReflectionCreateInstanceHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsReflectionCreateInstanceHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(
                fqPath: ["kotlin", "js", "ExperimentalJsReflectionCreateInstance"],
                sema: sema,
                interner: interner
            )
        )
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalJsReflectionCreateInstance must carry @Target metadata"
        )
        #expect(
            Set(target.arguments) == Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ])
        )
    }

    // MARK: - ExperimentalJsStatic (kotlin.js, WARNING)

    @Test func testExperimentalJsStaticIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.js.ExperimentalJsStatic must be registered in the symbol table")
    }

    @Test func testExperimentalJsStaticIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
    }

    @Test func testExperimentalJsStaticHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalJsStatic"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalJsStaticDoesNotCarryExplicitTargetMetadata() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalJsStatic"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)

        let hasTarget = annotations.contains { $0.annotationFQName == "kotlin.annotation.Target" }
        #expect(
            !hasTarget,
            "ExperimentalJsStatic should not carry explicit @Target metadata, got \(annotations)"
        )
    }

    // MARK: - ExperimentalWasmJsInterop (kotlin.js, WARNING)

    @Test func testExperimentalWasmJsInteropIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let sym = lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
        #expect(sym != nil, "kotlin.js.ExperimentalWasmJsInterop must be registered in the symbol table")
    }

    @Test func testExperimentalWasmJsInteropIsAnnotationClass() throws {
        let (sema, interner) = try makeSema()
        assertIsAnnotationClass(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
    }

    @Test func testExperimentalWasmJsInteropHasRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        assertHasRequiresOptIn(
            fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"],
            expectedSeverity: "WARNING",
            sema: sema,
            interner: interner
        )
    }

    @Test func testExperimentalWasmJsInteropHasOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try #require(
            lookupSymbol(fqPath: ["kotlin", "js", "ExperimentalWasmJsInterop"], sema: sema, interner: interner)
        )
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ExperimentalWasmJsInterop should carry explicit @Target metadata"
        )
        #expect(
            Set(target.arguments) == Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.TYPEALIAS",
            ])
        )
    }
}
#endif
