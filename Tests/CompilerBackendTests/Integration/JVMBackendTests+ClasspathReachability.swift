#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classpathReachabilityIncludesImplicitSignatureTypes() throws {
        try withWorkspace { root in
            let javaSources = [
                "Factory": "public class Factory { public static Payload make() { return new Payload(); } }",
                "Payload": "public class Payload { public String message() { return \"reachable\"; } }",
                "Unused": "public class Unused {}",
            ]
            let sourceNames = try javaSources.keys.sorted().map { name in
                let filename = name + ".java"
                try javaSources[name]!.write(to: root.appendingPathComponent(filename), atomically: true, encoding: .utf8)
                return filename
            }
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps"] + sourceNames, root: root)
            let classpath = root.appendingPathComponent("deps").path
            let source = "fun main() { println(Factory.make().message()) }"
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [classpath])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let options = CompilerOptions(
                moduleName: "JVMTest", inputs: [root.appendingPathComponent("hello.kt").path],
                outputPath: root.appendingPathComponent("hello.jar").path,
                emit: .jvmJar, target: .hostDefault(), jvmClasspath: [classpath]
            )
            let ctx = CompilationContext(
                options: options, sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(), interner: StringInterner()
            )
            try LoadSourcesPhase().run(ctx)
            try JVMPreparationPhase().run(ctx)
            let imports = try #require(ctx.jvmImports)
            #expect(imports.hasClassFile("Unused"))
            let stubs = imports.declarationFiles.compactMap { imports.sourceClasses[$0]?.name }
            #expect(Set(stubs) == ["Factory", "Payload"])

            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + classpath, "HelloKt"])
            #expect(execution.stdout == "reachable\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
