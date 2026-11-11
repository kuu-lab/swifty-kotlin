#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [false, true])
    func arrayMutationsRunOnRepositoryStdlib(precompiled: Bool) throws {
        let library = try ownStdlibLibrary()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/JVMOwnStdlib/arrayMutationABI.kt")
        try withWorkspace { root in
            let app = root.appendingPathComponent("app.jar")
            if precompiled {
                let compile = try jvmTool("kotlinc", ["-no-stdlib", "-no-reflect", "-cp", library.path, fixture.path, "-d", app.path], root: root)
                try #require(compile.exitCode == 0, "\(compile.stderr)")
            } else {
                let source = try String(contentsOf: fixture, encoding: .utf8)
                let compile = try m22Build(root: root, sources: [(fixture.lastPathComponent, source)], name: app.lastPathComponent, classpath: [library.path])
                try #require(compile.1 == 0, "\(compile.2.map(\.message))")
            }
            let run = try java(["-Xverify:all", "-cp", app.path + ":" + library.path, "ArrayMutationABIKt"])
            #expect(run.exitCode == 0, "\(run.stderr)")
            #expect(run.stdout == "ok\n")
        }
    }
}
#endif
