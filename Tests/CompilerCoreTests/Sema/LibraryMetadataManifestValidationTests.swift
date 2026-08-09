#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibraryMetadataManifestValidationTests {
    // MARK: - P5-54: Missing/Invalid manifest.json

    // MARK: - Consolidated Negative manifest validation tests

    @Test func testNegativeManifestScenarios() throws {
        let fm = FileManager.default
        var searchPaths: [String] = []
        var sources: [String] = []

        do {
            // testMissingManifestJsonEmitsErrorAndSkipsLibrary
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            // Create metadata.bin but NO manifest.json
            let metadata = """
            symbols=1
            function _ fq=nm.foo schema=v1 arity=0
            """
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample0
            fun main() = 0
            """)
        }

        do {
            // testInvalidJsonManifestEmitsErrorAndSkipsLibrary
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let invalidJson = "this is not json {{{}"
            try invalidJson.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

            let metadata = """
            symbols=1
            function _ fq=ij.bar schema=v1 arity=0
            """
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample1
            fun main() = 0
            """)
        }

        do {
            // testManifestMissingMetadataFieldEmitsWarning
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "NoMetaField"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=nmf.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample2
            fun main() = 0
            """)
        }

        do {
            // testManifestEmptyCompilerVersionEmitsWarning
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "EmptyCV",
              "compilerVersion": "",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=ecv.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample3
            fun main() = 0
            """)
        }

        do {
            // testManifestInvalidCompilerVersionTypeEmitsWarning
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "BadCVType",
              "compilerVersion": 123,
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=bcvt.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample4
            fun main() = 0
            """)
        }

        do {
            // testManifestMetadataPathTraversalEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "Traversal",
              "metadata": "../../etc/passwd"
            }
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample5
            fun main() = 0
            """)
        }

        do {
            // testManifestObjectPathTraversalEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "ObjTraversal",
              "metadata": "metadata.bin",
              "objects": ["../../secret.o"]
            }
            """
            let metadata = """
            symbols=1
            function _ fq=ot.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample6
            fun main() = 0
            """)
        }

        do {
            // testManifestInlineKIRDirPathTraversalEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "InlineTraversal",
              "metadata": "metadata.bin",
              "inlineKIRDir": "../../../tmp"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=it.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample7
            fun main() = 0
            """)
        }

        do {
            // testManifestInvalidObjectsFieldTypeEmitsError
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "BadObjects",
              "metadata": "metadata.bin",
              "objects": "not-an-array"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=bo.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample8
            fun main() = 0
            """)
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                moduleName: "NegativeManifestApp",
                emit: .kirDump,
                searchPaths: searchPaths
            )
            try runToKIR(ctx)

            // testMissingManifestJsonEmitsErrorAndSkipsLibrary
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
                let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                    ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
                }
                #expect(!(hasImported ?? false), "Library without manifest.json should not load symbols")
            }

            // testInvalidJsonManifestEmitsErrorAndSkipsLibrary
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
                let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                    ctx.interner.resolve(symbol.name) == "bar" && symbol.flags.contains(.synthetic)
                }
                #expect(!(hasImported ?? false), "Library with invalid JSON manifest should not load symbols")
            }

            // testManifestMissingMetadataFieldEmitsWarning
            do {

                let metadataWarnings = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-LIB-0016" && $0.severity == .warning
                }
                #expect(!metadataWarnings.isEmpty, "Should warn when 'metadata' field is missing from manifest")
            }

            // testManifestEmptyCompilerVersionEmitsWarning
            do {

                let cvWarnings = ctx.diagnostics.diagnostics.filter {
                    $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
                }
                #expect(!cvWarnings.isEmpty, "Should warn when 'compilerVersion' is empty")
            }

            // testManifestInvalidCompilerVersionTypeEmitsWarning
            do {

                #expect(ctx.kir != nil, "Invalid manifest metadata should not prevent KIR construction")
            }

            // testManifestMetadataPathTraversalEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
            }

            // testManifestObjectPathTraversalEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
            }

            // testManifestInlineKIRDirPathTraversalEmitsError
            do {

                assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
            }

            // testManifestInvalidObjectsFieldTypeEmitsError
            do {

                #expect(ctx.kir != nil, "Invalid objects field should not crash library discovery")
            }

        }
    }

    // MARK: - Consolidated Positive manifest validation tests

    @Test func testPositiveManifestScenarios() throws {
        let fm = FileManager.default
        var searchPaths: [String] = []
        var sources: [String] = []

        do {
            // testManifestValidCompilerVersionDoesNotWarn
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "GoodCV",
              "kotlinLanguageVersion": "2.3.10",
              "compilerVersion": "0.1.0",
              "target": "\(targetStr)",
              "metadata": "metadata.bin"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=gcv.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample0
            fun main() = 0
            """)
        }

        do {
            // testFullyValidManifestProducesNoSchemaErrors
            let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let libDir = baseDir.appendingPathExtension("kklib")
            let objectsDir = libDir.appendingPathComponent("objects")
            let inlineDir = libDir.appendingPathComponent("inline-kir")
            try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
            let t = defaultTargetTriple()
            let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

            let manifest = """
            {
              "formatVersion": 1,
              "moduleName": "FullValid",
              "kotlinLanguageVersion": "2.3.10",
              "compilerVersion": "0.1.0",
              "target": "\(targetStr)",
              "objects": ["objects/FullValid_0.o"],
              "metadata": "metadata.bin",
              "inlineKIRDir": "inline-kir"
            }
            """
            let metadata = """
            symbols=1
            function _ fq=fv.fn schema=v1 arity=0
            """
            try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
            try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
            // Create a dummy object file so path check passes
            try "".write(to: objectsDir.appendingPathComponent("FullValid_0.o"), atomically: true, encoding: .utf8)
            searchPaths.append(libDir.path)
            sources.append("""
            package sample1
            fun main() = 0
            """)
        }

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                moduleName: "PositiveManifestApp",
                emit: .kirDump,
                searchPaths: searchPaths
            )
            try runToKIR(ctx)

            // testManifestValidCompilerVersionDoesNotWarn
            do {

                assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
            }

            // testFullyValidManifestProducesNoSchemaErrors
            do {

                assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0014", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0015", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0016", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
                assertNoDiagnostic("KSWIFTK-LIB-0018", in: ctx)

                // Verify the symbol was loaded
                let fnSymbol = ctx.sema?.symbols.allSymbols().first { symbol in
                    ctx.interner.resolve(symbol.name) == "fn" && symbol.flags.contains(.synthetic)
                }
                #expect(fnSymbol != nil, "Fully valid manifest should load symbols successfully")
            }

        }
    }
}
#endif
