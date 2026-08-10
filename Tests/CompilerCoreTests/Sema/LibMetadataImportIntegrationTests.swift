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

    /// KSP-461: an unparsable instruction used to be dropped silently, leaving the
    /// following instructions reading registers that were never defined (the call
    /// site then produced garbage). The whole body must be rejected instead.
    @Test func testInlineKIRArtifactWithUnsupportedInstructionIsRejected() throws {
        let ctx = try compileWithInlineKIRBody(
            moduleName: "UnsupportedInline",
            body: """
            beginBlock
            totallyUnknownOpcode result=1
            returnValue value=1
            """
        )
        assertHasDiagnostic("KSWIFTK-LIB-0023", in: ctx)
    }

    /// KSP-461: `virtualCall` is emitted into inline KIR artifacts (any inline
    /// stdlib function that dispatches through an interface, e.g. a `Comparator`
    /// parameter), so the importer has to understand it.
    @Test func testInlineKIRArtifactWithVirtualCallIsImported() throws {
        let ctx = try compileWithInlineKIRBody(
            moduleName: "VirtualCallInline",
            body: """
            beginBlock
            virtualCall symbol=_ calleeB64=\(base64("compare")) receiver=1 args=[2,3] result=4 canThrow=1 thrownResult=_ dispatch=itableDynamic:12345:0
            virtualCall symbol=_ calleeB64=\(base64("size")) receiver=1 args=[] result=5 canThrow=0 thrownResult=_ dispatch=itable:0:1
            virtualCall symbol=_ calleeB64=\(base64("hashCode")) receiver=1 args=[] result=6 canThrow=0 thrownResult=_ dispatch=vtable:2
            returnValue value=4
            """
        )
        assertNoDiagnostic("KSWIFTK-LIB-0023", in: ctx)
    }

    private func base64(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    /// Builds a one-function library whose inline KIR artifact contains `body`,
    /// then compiles a trivial program against it.
    private func compileWithInlineKIRBody(
        moduleName: String,
        body: String
    ) throws -> CompilationContext {
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
          "moduleName": "\(moduleName)",
          "kotlinLanguageVersion": "2.3.10",
          "target": "\(targetStr)",
          "metadata": "metadata.bin",
          "inlineKIRDir": "inline-kir"
        }
        """
        let metadata = """
        symbols=1
        function InlineBody fq=lib.foo schema=v1 arity=0 suspend=0 inline=1
        """
        let kirbin = """
        version=2
        params=0
        suspend=false
        body:
        \(body)
        """

        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try kirbin.write(to: inlineDir.appendingPathComponent("InlineBody.kirbin"), atomically: true, encoding: .utf8)

        var result: CompilationContext!
        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName + "App",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )
            try runToKIR(ctx)
            result = ctx
        }
        return result
    }
}
#endif
