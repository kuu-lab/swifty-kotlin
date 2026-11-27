import Foundation
import PackagePlugin

@main
struct VerifyLeanParser: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let root = context.package.directoryURL
        let resources = root.appendingPathComponent("Sources/CompilerCore/LeanParserResources")
        let source = root.appendingPathComponent("Sources/LeanParser")
        let proofs = source.appendingPathComponent("ParserProofs")
        let buildScript = root.appendingPathComponent("Scripts/build_lean.sh")
        let sources = ["Bridge.c", "lakefile.toml", "lake-manifest.json", "lean-toolchain"]
            .map { source.appendingPathComponent($0) }
        let proofFiles = FileManager.default.enumerator(at: proofs, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "lean" } ?? []
        let outputDirectory = context.pluginWorkDirectoryURL
        let output = outputDirectory.appendingPathComponent("VerifiedLeanParser.swift")
        #if os(macOS)
        let libraries = ["liblean_parser.dylib"]
        #else
        let libraries = ["liblean_parser.so", "libleanshared.so"]
        #endif
        let identity = root.appendingPathComponent("Sources/CompilerCore/Parser/LeanParserBuildIdentity.swift")
        let artifacts = ((libraries + [".lean-parser-fingerprint", ".build-id"])
            .map { resources.appendingPathComponent($0) } + [identity])
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return [
            .buildCommand(
                displayName: "Verify bundled Lean parser",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c", """
                    set -eu
                    /bin/bash "$1" --verify
                    mkdir -p "$2"
                    : > "$3"
                    """,
                    "verify-lean-parser", buildScript.path, outputDirectory.path, output.path,
                ],
                inputFiles: [resources, proofs, buildScript] + sources + proofFiles + artifacts,
                outputFiles: [output]
            )
        ]
    }
}
