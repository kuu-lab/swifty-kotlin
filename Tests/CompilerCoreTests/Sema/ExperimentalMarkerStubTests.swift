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

    @Test
    func testExperimentalMarkerStubSema() throws {
        let markerRecords: [(
            name: String,
            packagePath: [String],
            severity: String,
            messageHint: String?,
            targets: [String]?,
            retention: String?
        )] = [
            ("ExperimentalUnsignedTypes", ["kotlin"], "ERROR", nil, nil, nil),
            ("ExperimentalVersionOverloading", ["kotlin"], "ERROR", nil, nil, nil),
            ("ExperimentalContextParameters", ["kotlin"], "ERROR", "context parameters", nil, nil),
            ("ExperimentalUuidApi", ["kotlin", "uuid"], "ERROR", nil, nil, nil),
            ("ExperimentalEncodingApi", ["kotlin", "io", "encoding"], "ERROR", nil, nil, nil),
            (
                "ExperimentalPathApi",
                ["kotlin", "io", "path"],
                "ERROR",
                nil,
                [
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
                ],
                nil
            ),
            ("ExperimentalAssociatedObjects", ["kotlin", "reflect"], "ERROR", nil, nil, "AnnotationRetention.BINARY"),
            ("ExperimentalMultiplatform", ["kotlin"], "ERROR", nil, nil, nil),
            ("ExperimentalSubclassOptIn", ["kotlin"], "WARNING", nil, nil, nil),
        ]

        var sources: [String] = []
        sources.append("fun noop() {}")

        var optInMarkerSourceIndices: [(name: String, withoutIndex: Int, withIndex: Int)] = []
        for marker in Self.optInExperimentalPackageMarkerNames {
            let withoutIndex = sources.count
            sources.append("""
            package marker_use_\(marker)
            import kotlin.annotation.Target
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """)
            let withIndex = sources.count
            sources.append("""
            @file:OptIn(kotlin.experimental.\(marker)::class)
            package marker_use_\(marker)_optin
            import kotlin.annotation.Target
            import kotlin.experimental.\(marker)

            @\(marker)
            @Target(AnnotationTarget.FUNCTION)
            annotation class Uses\(marker)

            @Uses\(marker)
            fun experimental\(marker)(): Int = 1

            fun use\(marker)(): Int = experimental\(marker)()
            """)
            optInMarkerSourceIndices.append((name: marker, withoutIndex: withoutIndex, withIndex: withIndex))
        }

        var expectRefinementSourceIndices: [(name: String, aIndex: Int, bIndex: Int)] = []

        // Refined expect/actual with @file:OptIn
        do {
            let aIndex = sources.count
            sources.append("""
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)
            package sample.exp1
            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class Refined
            """)
            let bIndex = sources.count
            sources.append("""
            package sample.exp1

            actual class Refined
            """)
            expectRefinementSourceIndices.append((name: "Refined", aIndex: aIndex, bIndex: bIndex))
        }

        // NeedsOptIn expect/actual without @file:OptIn
        do {
            let aIndex = sources.count
            sources.append("""
            package sample.exp2
            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class NeedsOptIn

            fun echo(value: NeedsOptIn): NeedsOptIn = value
            """)
            let bIndex = sources.count
            sources.append("""
            package sample.exp2

            actual class NeedsOptIn
            """)
            expectRefinementSourceIndices.append((name: "NeedsOptIn", aIndex: aIndex, bIndex: bIndex))
        }

        // RefinedWithOptIn expect/actual with @file:OptIn
        do {
            let aIndex = sources.count
            sources.append("""
            @file:OptIn(kotlin.ExperimentalMultiplatform::class)
            package sample.exp3
            import kotlin.experimental.ExpectRefinement

            @ExpectRefinement
            expect class RefinedWithOptIn

            fun echo(value: RefinedWithOptIn): RefinedWithOptIn = value
            """)
            let bIndex = sources.count
            sources.append("""
            package sample.exp3

            actual class RefinedWithOptIn
            """)
            expectRefinementSourceIndices.append((name: "RefinedWithOptIn", aIndex: aIndex, bIndex: bIndex))
        }

        // ExpectRefinement reject function target
        let functionTargetRejectionIndex = sources.count
        sources.append("""
        @file:OptIn(kotlin.ExperimentalMultiplatform::class)
        package sample.reject
        import kotlin.experimental.ExpectRefinement

        @ExpectRefinement
        fun invalidRefinementTarget() {}
        """)

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            func diagnosticsForPath(_ path: String) -> [Diagnostic] {
                guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
                return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
            }

            func lookupSymbol(fqPath: [String]) -> SymbolID? {
                return sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
            }

            func assertIsAnnotationClass(fqPath: [String]) {
                guard let sym = lookupSymbol(fqPath: fqPath),
                      let info = sema.symbols.symbol(sym)
                else {
                    Issue.record("\(fqPath.joined(separator: ".")) not found in symbol table")
                    return
                }
                #expect(info.kind == .annotationClass, "\(fqPath.last ?? "") must have kind=annotationClass")
            }

            func assertHasRequiresOptIn(fqPath: [String], expectedSeverity: String) {
                guard let sym = lookupSymbol(fqPath: fqPath) else {
                    Issue.record("\(fqPath.joined(separator: ".")) not found in symbol table")
                    return
                }
                let annotations = sema.symbols.annotations(for: sym)
                guard let requiresOptIn = annotations.first(where: { $0.annotationFQName == "kotlin.RequiresOptIn" }) else {
                    Issue.record("\(fqPath.last ?? "") must carry @RequiresOptIn annotation")
                    return
                }
                let hasSeverity = requiresOptIn.arguments.contains { $0.contains(expectedSeverity) }
                #expect(hasSeverity, "\(fqPath.last ?? "") @RequiresOptIn must declare severity=\(expectedSeverity); got \(requiresOptIn.arguments)")
            }

            // Synthetic marker registration / kind / severity / targets / retention
            for record in markerRecords {
                let fqPath = record.packagePath + [record.name]

                let symbol = lookupSymbol(fqPath: fqPath)
                #expect(symbol != nil, "\(fqPath.joined(separator: ".")) must be registered in the symbol table")

                assertIsAnnotationClass(fqPath: fqPath)
                assertHasRequiresOptIn(fqPath: fqPath, expectedSeverity: record.severity)

                if record.name == "ExperimentalEncodingApi" {
                    #expect(
                        lookupSymbol(fqPath: ["kotlin", "io", "encoding"]) != nil,
                        "kotlin.io.encoding package must be present in the symbol table after sema"
                    )
                }

                if let messageHint = record.messageHint {
                    let sym = try #require(lookupSymbol(fqPath: fqPath))
                    let annotations = sema.symbols.annotations(for: sym)
                    let requiresOptIn = try #require(annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" })
                    #expect(
                        requiresOptIn.arguments.contains { $0.contains(messageHint) },
                        "Expected \(record.name) @RequiresOptIn message to mention \(messageHint), got: \(requiresOptIn.arguments)"
                    )
                }

                if let targets = record.targets {
                    let sym = try #require(lookupSymbol(fqPath: fqPath))
                    let annotations = sema.symbols.annotations(for: sym)
                    #expect(
                        annotations.contains {
                            $0.annotationFQName == "kotlin.annotation.Target" && $0.arguments == targets
                        },
                        "\(record.name) must carry the official @Target list, got \(annotations)"
                    )
                }

                if let retention = record.retention {
                    let sym = try #require(lookupSymbol(fqPath: fqPath))
                    let annotations = sema.symbols.annotations(for: sym)
                    #expect(
                        annotations.contains {
                            $0.annotationFQName == "kotlin.annotation.Retention"
                                && $0.arguments.contains(retention)
                        },
                        "Expected \(record.name) to carry @Retention(\(retention)), got: \(annotations)"
                    )
                }
            }

            // Severity cross-check: ERROR vs WARNING are distinct
            do {
                func severity(fqPath: [String]) -> String? {
                    guard let sym = lookupSymbol(fqPath: fqPath) else { return nil }
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

            // Kotlin experimental marker inventory
            do {
                let targetMarkers = Self.implementedExperimentalPackageMarkers.union(Self.knownGapExperimentalPackageMarkers)
                let targetNames = Set(targetMarkers.map(\.name))

                #expect(targetMarkers.count == targetNames.count)
                #expect(targetMarkers.count == 6)
                #expect(Self.implementedExperimentalPackageMarkers.count == 6)
                #expect(Self.knownGapExperimentalPackageMarkers.count == 0)
            }

            // Implemented kotlin.experimental markers are registered as annotation classes
            for marker in Self.implementedExperimentalPackageMarkers {
                let symbol = try #require(
                    lookupSymbol(fqPath: ["kotlin", "experimental", marker.name]),
                    "kotlin.experimental.\(marker.name) must be registered in the symbol table"
                )
                #expect(
                    sema.symbols.symbol(symbol)?.kind == .annotationClass,
                    "kotlin.experimental.\(marker.name) should be an annotation class"
                )
            }

            // Known gaps remain absent
            for marker in Self.knownGapExperimentalPackageMarkers {
                let symbol = lookupSymbol(fqPath: ["kotlin", "experimental", marker.name])
                #expect(
                    symbol == nil,
                    "kotlin.experimental.\(marker.name) is tracked by \(marker.todo ?? "unknown TODO") and should update this inventory when implemented"
                )
            }

            // Known gap TODOs are scoped
            do {
                let todos = Set(Self.knownGapExperimentalPackageMarkers.compactMap(\.todo))
                #expect(todos == Set<String>())
            }

            // Opt-in markers carry ERROR-level @RequiresOptIn in kotlin.experimental
            for marker in Self.optInExperimentalPackageMarkerNames {
                let symbol = try #require(
                    lookupSymbol(fqPath: ["kotlin", "experimental", marker]),
                    "kotlin.experimental.\(marker) must be registered in the symbol table"
                )
                let annotations = sema.symbols.annotations(for: symbol)
                #expect(
                    annotations.contains {
                        $0.annotationFQName == "kotlin.RequiresOptIn"
                            && $0.arguments.contains("level=RequiresOptIn.Level.ERROR")
                    },
                    "kotlin.experimental.\(marker) should carry @RequiresOptIn(ERROR), got \(annotations)"
                )
            }

            // Opt-in markers emit diagnostics on use and accept explicit opt-in
            for entry in optInMarkerSourceIndices {
                let withoutPath = paths[entry.withoutIndex]
                let withoutDiagnostics = diagnosticsForPath(withoutPath).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
                #expect(
                    withoutDiagnostics.contains { $0.severity == .error },
                    "Expected \(entry.name) use to emit an opt-in error, got \(ctx.diagnostics.diagnostics)"
                )

                let withPath = paths[entry.withIndex]
                let withDiagnostics = diagnosticsForPath(withPath).filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
                #expect(
                    withDiagnostics.isEmpty,
                    "Expected @OptIn(\(entry.name)::class) to suppress opt-in diagnostics, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // ExpectRefinement class target and ExperimentalMultiplatform metadata
            do {
                let symbol = try #require(
                    lookupSymbol(fqPath: ["kotlin", "experimental", "ExpectRefinement"]),
                    "kotlin.experimental.ExpectRefinement must be registered in the symbol table"
                )
                let annotations = sema.symbols.annotations(for: symbol)
                #expect(
                    annotations.contains {
                        $0.annotationFQName == "kotlin.annotation.Target" && $0.arguments == ["AnnotationTarget.CLASS"]
                    },
                    "ExpectRefinement should carry @Target(AnnotationTarget.CLASS), got \(annotations)"
                )
                #expect(
                    annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" },
                    "ExpectRefinement should carry @ExperimentalMultiplatform, got \(annotations)"
                )
            }

            // ExpectRefinement metadata exposed on expect declaration
            if let refined = expectRefinementSourceIndices.first(where: { $0.name == "Refined" }) {
                let samplePaths = [paths[refined.aIndex], paths[refined.bIndex]]
                let errors = ctx.diagnostics.diagnostics.filter { d in
                    guard d.severity == .error else { return false }
                    guard let fileID = d.primaryRange?.start.file else { return false }
                    return Set(samplePaths.compactMap { ctx.sourceManager.fileID(forPath: $0) }).contains(fileID)
                }
                #expect(
                    errors.isEmpty,
                    "Expected expect/actual refined class to compile cleanly, got \(ctx.diagnostics.diagnostics)"
                )

                let fqName = ["sample", "exp1", "Refined"].map { interner.intern($0) }
                let refinedSymbol = try #require(
                    sema.symbols.lookupAll(fqName: fqName).first { symbolID in
                        sema.symbols.symbol(symbolID)?.flags.contains(.expectDeclaration) == true
                    },
                    "sample.exp1.Refined expect declaration must be visible"
                )
                let annotations = sema.symbols.annotations(for: refinedSymbol)
                #expect(
                    annotations.contains {
                        $0.annotationFQName == "kotlin.experimental.ExpectRefinement"
                            || $0.annotationFQName == "ExpectRefinement"
                    },
                    "Expected @ExpectRefinement metadata on expect declaration, got \(annotations)"
                )
            }

            // ExpectRefinement use requires ExperimentalMultiplatform opt-in
            if let needsOptIn = expectRefinementSourceIndices.first(where: { $0.name == "NeedsOptIn" }) {
                let samplePaths = [paths[needsOptIn.aIndex], paths[needsOptIn.bIndex]]
                let sampleFileIDs = Set(samplePaths.compactMap { ctx.sourceManager.fileID(forPath: $0) })
                let diagnostics = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN" && sampleFileIDs.contains($0.primaryRange?.start.file ?? FileID(rawValue: -1))
                }
                #expect(
                    diagnostics.contains { $0.severity == .error && $0.message.contains("kotlin.ExperimentalMultiplatform") },
                    "Expected ExpectRefinement usage to require ExperimentalMultiplatform opt-in, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // ExpectRefinement accepts ExperimentalMultiplatform opt-in
            if let refinedWithOptIn = expectRefinementSourceIndices.first(where: { $0.name == "RefinedWithOptIn" }) {
                let samplePaths = [paths[refinedWithOptIn.aIndex], paths[refinedWithOptIn.bIndex]]
                let sampleFileIDs = Set(samplePaths.compactMap { ctx.sourceManager.fileID(forPath: $0) })
                let diagnostics = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN" && sampleFileIDs.contains($0.primaryRange?.start.file ?? FileID(rawValue: -1))
                }
                #expect(
                    diagnostics.isEmpty,
                    "Expected @OptIn(kotlin.ExperimentalMultiplatform::class) to suppress ExpectRefinement diagnostics, got \(ctx.diagnostics.diagnostics)"
                )
            }

            // ExpectRefinement rejects function target
            do {
                let rejectionPath = paths[functionTargetRejectionIndex]
                let diagnostics = diagnosticsForPath(rejectionPath).filter { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" }
                #expect(
                    diagnostics.count == 1,
                    "Expected ExpectRefinement to reject function target, got \(ctx.diagnostics.diagnostics)"
                )
                #expect(
                    diagnostics.allSatisfy { $0.severity == .error },
                    "ExpectRefinement target diagnostics should be errors"
                )
            }
        }
    }
}
#endif
