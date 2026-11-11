#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func apkCompilesAgainstResourceIDsFromItsOwnLink() throws {
        try withWorkspace { root in
            let fileManager = FileManager.default
            let tools = root.appendingPathComponent("build-tools/36.1.0", isDirectory: true)
            let platform = root.appendingPathComponent("platforms/android-36.1", isDirectory: true)
            let res = root.appendingPathComponent("res", isDirectory: true)
            for directory in [tools, platform, res] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            _ = try jvmTool("jar", ["cf", platform.appendingPathComponent("android.jar").path, "-C", res.path, "."], root: root)
            func writeTool(_ name: String, _ body: String) throws {
                let path = tools.appendingPathComponent(name)
                try ("#!/bin/sh\nset -eu\n" + body + "\n").write(to: path, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            }
            try writeTool("aapt2", #"""
                operation=$1; shift
                while [ "$#" -gt 0 ]; do
                    case "$1" in
                        -o) output=$2; shift ;;
                        --manifest) manifest=$2; shift ;;
                        --java) generated=$2; shift ;;
                    esac
                    shift
                done
                if [ "$operation" = compile ]; then
                    : > "$output"
                    exit 0
                fi
                marker="$(dirname "$0")/linked"
                test ! -e "$marker"
                touch "$marker"
                zip -q -j "$output" "$manifest"
                mkdir -p "$generated/app"
                cat > "$generated/app/R.java" <<'EOF'
                package app;
                public final class R {
                    public static final class layout {
                        public static final int counter = 0x7f020000;
                    }
                }
                EOF
                """#)
            try writeTool("d8", #"""
                for arg do
                    if [ "$arg" = --output ]; then
                        output_next=1
                    elif [ "${output_next:-0}" = 1 ]; then
                        output=$arg
                        output_next=0
                    fi
                    last=$arg
                done
                cp "$last" "$(dirname "$0")/program.jar"
                printf 'test dex' > "$output/classes.dex"
                """#)
            try writeTool("apksigner", #"""
                for arg do
                    if [ "$arg" = --out ]; then
                        output_next=1
                    elif [ "${output_next:-0}" = 1 ]; then
                        output=$arg
                        output_next=0
                    fi
                    last=$arg
                done
                cp "$last" "$output"
                """#)
            let manifest = root.appendingPathComponent("AndroidManifest.xml")
            let keystore = root.appendingPathComponent("debug.keystore")
            let input = root.appendingPathComponent("probe.kt")
            let output = root.appendingPathComponent("app.apk")
            try Data("<manifest package=\"app\"/>".utf8).write(to: manifest)
            try Data().write(to: keystore)
            try Data("package app\nfun main() { println(R.layout.counter) }\n".utf8).write(to: input)
            let options = CompilerOptions(
                moduleName: "ResourceApp", inputs: [input.path], outputPath: output.path, emit: .apk,
                target: .hostDefault(), android: .init(
                    sdkPath: root.path, manifestPath: manifest.path, resourcePath: res.path, keystorePath: keystore.path
                )
            )
            let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
            try #require(result.exitCode == 0, "\(result.diagnostics.map(\.message))")
            let apk = try ZipArchive(data: Data(contentsOf: output))
            #expect(Set(apk.entries.map(\.name)) == ["AndroidManifest.xml", "classes.dex"])
            let program = tools.appendingPathComponent("program.jar")
            let jar = try ZipArchive(data: Data(contentsOf: program))
            #expect(jar.entries.contains { $0.name == "app/R$layout.class" })
            let execution = try java(["-cp", program.path, "app.ProbeKt"])
            #expect(execution.stdout == "2130837504\n")
        }
    }
}
#endif
