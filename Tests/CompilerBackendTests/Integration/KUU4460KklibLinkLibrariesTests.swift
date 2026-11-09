@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct KUU4460KklibLinkLibrariesTests {
    /// KUU-4460: `-l<name>` resolving to `<name>.kklib`/`lib<name>.kklib` under
    /// `-I` must consume the bundle's objects instead of reaching `ld` as a
    /// native `-l` flag. Native archives in the same `-l` list keep working.
    @Test func kklibDashLLinksBundleObjectsAndKeepsNativeLibs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()

        func compile(
            source: String, module: String, emit: EmitMode,
            searchPaths: [String] = [], libraryPaths: [String] = [],
            linkLibraries: [String] = []
        ) throws -> String {
            let sourcePath = directory.appendingPathComponent(module + ".kt").path
            let output = directory.appendingPathComponent(module).path
            try source.write(toFile: sourcePath, atomically: true, encoding: .utf8)
            let options = CompilerOptions(
                moduleName: module, inputs: [sourcePath], outputPath: output,
                emit: emit, searchPaths: searchPaths, libraryPaths: libraryPaths,
                linkLibraries: linkLibraries,
                target: defaultTargetTriple(), includeStdlib: false,
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options), context: module)
            return emit == .library ? output + ".kklib" : output
        }

        let library = try compile(
            source: "package tiny\nfun answer(): Int = 42\n",
            module: "Libtiny", emit: .library
        )
        // `-l tiny` must resolve `libtiny.kklib` inside the `-I` directory.
        let libDir = directory.appendingPathComponent("libs")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: URL(fileURLWithPath: library),
            to: libDir.appendingPathComponent("libtiny.kklib")
        )
        // A native archive alongside the kklib stays a native `-l` input.
        // Its member duplicates an object the kklib already contributes, so
        // `ld` never extracts it — the archive only proves forwarding works.
        let objects = try FileManager.default.contentsOfDirectory(
            atPath: libDir.appendingPathComponent("libtiny.kklib/objects").path
        ).filter { $0.hasSuffix(".o") }
        try #require(!objects.isEmpty)
        let nativeArchive = libDir.appendingPathComponent("libTinyNative.a").path
        let archiveResult = try CommandRunner.run(
            executable: CommandRunner.resolveExecutable("ar", fallback: "/usr/bin/ar"),
            arguments: ["rcs", nativeArchive]
                + objects.map { libDir.appendingPathComponent("libtiny.kklib/objects/" + $0).path }
        )
        try #require(archiveResult.exitCode == 0, "Archive stderr: \(archiveResult.stderr)")

        let executable = try compile(
            source: "import tiny.*\nfun main() { println(answer()) }\n",
            module: "Consumer", emit: .executable,
            searchPaths: [libDir.path], libraryPaths: [libDir.path],
            linkLibraries: ["tiny", "TinyNative"]
        )
        let result = try CommandRunner.run(executable: executable, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stdout == "42\n")
    }
}
