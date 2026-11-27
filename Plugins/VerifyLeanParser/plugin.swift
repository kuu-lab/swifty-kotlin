import Foundation
import PackagePlugin

@main
struct VerifyLeanParser: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let resources = context.package.directoryURL
            .appendingPathComponent("Sources/CompilerCore/LeanParserResources")
        let outputDirectory = context.pluginWorkDirectoryURL
        let output = outputDirectory.appendingPathComponent("VerifiedLeanParser.swift")
        #if os(macOS)
        let libraries = ["liblean_parser.dylib"]
        #else
        let libraries = ["liblean_parser.so", "libleanshared.so"]
        #endif
        let libraryURLs = libraries.map { resources.appendingPathComponent($0) }
        let existingLibraries = libraryURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        return [
            .buildCommand(
                displayName: "Verify bundled Lean parser",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c", """
                    set -eu
                    output=$1
                    directory=$2
                    shift 2
                    for library do
                        if [ ! -s "$library" ]; then
                            printf 'error: Missing Lean parser resource %s. Run bash Scripts/build_lean.sh from the repository root.\u{5c}n' "$library" >&2
                            exit 1
                        fi
                    done
                    mkdir -p "$directory"
                    : > "$output"
                    """,
                    "verify-lean-parser", output.path, outputDirectory.path,
                ] + libraryURLs.map(\.path),
                inputFiles: [resources] + existingLibraries,
                outputFiles: [output]
            )
        ]
    }
}
