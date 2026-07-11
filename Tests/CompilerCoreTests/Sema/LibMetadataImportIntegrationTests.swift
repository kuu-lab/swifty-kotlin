#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct LibMetadataImportIntegrationTests {
    // MARK: - Manifest Schema Validation Tests

    @Test func testManifestMissingFormatVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "moduleName": "NoVersion",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nv.foo schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoVersionApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            let noSymbols = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "foo" && symbol.flags.contains(.synthetic)
            }
            #expect(!(noSymbols ?? false))
        }
    }

    @Test func testManifestUnsupportedFormatVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 99,
          "moduleName": "BadVersion",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bv.bar schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadVersionApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0010", in: ctx)
        }
    }

    @Test func testManifestMissingModuleNameEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=nm.baz schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoModuleNameApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
        }
    }

    @Test func testManifestEmptyModuleNameEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=em.qux schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EmptyModuleNameApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0011", in: ctx)
        }
    }

    @Test func testManifestUnsupportedKotlinLanguageVersionEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BadLang",
          "kotlinLanguageVersion": "1.9.0",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=bl.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "BadLangApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0012", in: ctx)
        }
    }

    @Test func testManifestIncompatibleTargetEmitsErrorAndSkipsLibrary() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "WrongTarget",
          "kotlinLanguageVersion": "2.3.10",
          "target": "fake-unknown-invalid",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=wt.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "WrongTargetApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0013", in: ctx)
            let hasImported = ctx.sema?.symbols.allSymbols().contains { symbol in
                ctx.interner.resolve(symbol.name) == "fn" && symbol.flags.contains(.synthetic)
            }
            #expect(!(hasImported ?? false))
        }
    }

    @Test func testManifestCompatibleTargetDoesNotEmitTargetError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "GoodTarget",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=gt.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "GoodTargetApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertNoDiagnostic("KSWIFTK-LIB-0010", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0011", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0012", in: ctx)
            assertNoDiagnostic("KSWIFTK-LIB-0013", in: ctx)
        }
    }

    @Test func testManifestMissingMetadataFileEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NoMeta",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "nonexistent.bin"
        }
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "NoMetaApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0014", in: ctx)
        }
    }

    @Test func testManifestMissingObjectFileEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MissingObj",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "objects": ["objects/missing.o"],
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=mo.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MissingObjApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let pathWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
            }
            #expect(!pathWarnings.isEmpty)
        }
    }

    @Test func testManifestMissingInlineKIRDirEmitsWarning() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "MissingInline",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "nonexistent-dir"
        }
        """
        let metadata = """
        symbols=1
        function _ fq=mi.fn schema=v1 arity=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "MissingInlineApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            let pathWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-LIB-0014" && $0.severity == .warning
            }
            #expect(!pathWarnings.isEmpty)
        }
    }

    @Test func testInlineKIRArtifactWithExcessiveParameterCountEmitsError() throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let libDir = baseDir.appendingPathExtension("kklib")
        let inlineDir = libDir.appendingPathComponent("inline-kir")
        try fm.createDirectory(at: inlineDir, withIntermediateDirectories: true)
        let t = defaultTargetTriple()
        let targetStr = "\(t.arch)-\(t.vendor)-\(t.os)"

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "HugeInline",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function HugeParams fq=lib.foo schema=v1 arity=0 suspend=0 inline=1
        """
        let kirbin = "params=2000000000\n"

        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try kirbin.write(to: inlineDir.appendingPathComponent("HugeParams.kirbin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "HugeInlineApp",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)

            assertHasDiagnostic("KSWIFTK-LIB-0020", in: ctx)
        }
    }
}
#endif
