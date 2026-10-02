#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite
struct LibraryMetadataManifestValidationTests {
    // MARK: - P5-54: Missing/Invalid manifest.json

    @Test func testMissingManifestJsonEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Create metadata.bin but NO manifest.json
        let metadata = """
        symbols=1
        function _ fq=nm.foo schema=v1 arity=0
        """
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoManifestApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
            }
            #expect(!(hasImported ?? false), "Library without manifest.json should not load symbols")
        }
    }

    @Test func testInvalidJsonManifestEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InvalidJsonApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0015", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "bar" && symbol.flags.contains(.synthetic)
            }
            #expect(!(hasImported ?? false), "Library with invalid JSON manifest should not load symbols")
        }
    }

    // MARK: - P5-54: Missing metadata field warning

    @Test func testManifestMissingMetadataFieldEmitsWarning() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoMetaFieldApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let metadataWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0016" && $0.severity == .warning
            }
            #expect(!metadataWarnings.isEmpty, "Should warn when 'metadata' field is missing from manifest")
        }
    }

    // MARK: - P5-54: compilerVersion validation

    @Test func testManifestEmptyCompilerVersionEmitsWarning() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EmptyCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let cvWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0017" && $0.severity == .warning
            }
            #expect(!cvWarnings.isEmpty, "Should warn when 'compilerVersion' is empty")
        }
    }

    @Test func testManifestInvalidCompilerVersionTypeEmitsWarning() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadCVTypeApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            #expect(ctx.kir != nil, "Invalid manifest metadata should not prevent KIR construction")
        }
    }

    @Test func testManifestValidCompilerVersionDoesNotWarn() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GoodCVApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0017", in: ctx)
        }
    }

    // MARK: - P5-54: Path traversal protection

    @Test func testManifestSymlinkOutsideLibraryEmitsErrorWithoutReadingIt() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let outsideManifest = baseDir.appendingPathComponent("outside-manifest.json")
        try #"{"formatVersion":1,"moduleName":"OutsideManifest"}"#.write(
            to: outsideManifest,
            atomically: true,
            encoding: .utf8
        )
        try fm.createSymbolicLink(
            at: libDir.appendingPathComponent("manifest.json"),
            withDestinationURL: outsideManifest
        )

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ManifestSymlinkApp", emit: .kirDump, searchPaths: [libDir.path]
            )
            try runToKIR(ctx)
            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    @Test func testManifestMetadataPathTraversalEmitsError() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "TraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    @Test func testManifestMetadataSymlinkOutsideLibraryEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let outsideMetadata = baseDir.appendingPathComponent("outside-metadata.bin")
        try "symbols=0\n".write(to: outsideMetadata, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            at: libDir.appendingPathComponent("metadata.bin"),
            withDestinationURL: outsideMetadata
        )
        let manifest = """
        {"formatVersion":1,"moduleName":"MetadataSymlink","metadata":"metadata.bin"}
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "MetadataSymlinkApp", emit: .kirDump, searchPaths: [libDir.path]
            )
            try runToKIR(ctx)
            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    @Test func testManifestObjectPathTraversalEmitsError() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "ObjTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    @Test func testManifestObjectSymlinkOutsideLibraryEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let objectsDir = libDir.appendingPathComponent("objects")
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        let outsideObject = baseDir.appendingPathComponent("outside.o")
        try Data().write(to: outsideObject)
        try fm.createSymbolicLink(
            at: objectsDir.appendingPathComponent("external.o"),
            withDestinationURL: outsideObject
        )
        try "symbols=0\n".write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let manifest = """
        {"formatVersion":1,"moduleName":"ObjectSymlink","metadata":"metadata.bin","objects":["objects/external.o"]}
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ObjectSymlinkApp", emit: .kirDump, searchPaths: [libDir.path]
            )
            try runToKIR(ctx)
            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    @Test func testManifestObjectFIFOEmitsErrorWithoutReadingIt() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let objectsDir = libDir.appendingPathComponent("objects")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try "symbols=0\n".write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        let fifoPath = objectsDir.appendingPathComponent("blocked.o").path
        let fifoResult = fifoPath.withCString { mkfifo($0, mode_t(S_IRUSR | S_IWUSR)) }
        guard fifoResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let manifest = """
        {"formatVersion":1,"moduleName":"ObjectFIFO","metadata":"metadata.bin","objects":["objects/blocked.o"]}
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ObjectFIFOApp", emit: .kirDump, searchPaths: [libDir.path]
            )
            try runToKIR(ctx)
            assertHasDiagnostic("KSWIFTK-LIB-0014", in: ctx)
        }
    }

    @Test func testManifestInlineKIRDirPathTraversalEmitsError() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "InlineTraversalApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0018", in: ctx)
        }
    }

    // MARK: - P5-54: Invalid objects field type

    @Test func testManifestInvalidObjectsFieldTypeEmitsError() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadObjectsApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            #expect(ctx.kir != nil, "Invalid objects field should not crash library discovery")
        }
    }

    // MARK: - P5-54: Full valid manifest with all fields passes cleanly

    @Test func testFullyValidManifestProducesNoSchemaErrors() throws {
        let fm = FileManager.default
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

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FullValidApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

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
#endif
