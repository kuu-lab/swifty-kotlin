import Foundation
import PackagePlugin

@main
struct VerifyLeanParser: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let resources = context.package.directoryURL
            .appendingPathComponent("Sources/CompilerCore/LeanParserResources")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("VerifiedLeanParser")
        #if os(macOS)
        let libraries = ["liblean_parser.dylib"]
        #else
        let libraries = ["liblean_parser.so", "libleanshared.so"]
        #endif
        return [
            .prebuildCommand(
                displayName: "Verify bundled Lean parser",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c", """
                    set -eu
                    output=$1
                    shift
                    for library do
                        if [ ! -s "$library" ]; then
                            printf 'error: Missing Lean parser resource %s. Run bash Scripts/build_lean.sh from the repository root.\u{5c}n' "$library" >&2
                            exit 1
                        fi
                    done
                    mkdir -p "$output"
                    """,
                    "verify-lean-parser", output.path,
                ] + libraries.map { resources.appendingPathComponent($0).path },
                outputFilesDirectory: output
            )
        ]
    }
}
