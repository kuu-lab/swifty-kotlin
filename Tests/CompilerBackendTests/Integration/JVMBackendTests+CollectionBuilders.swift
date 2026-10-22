#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionBuildersPreserveCompletionReturnsAndEscapedReceiverState(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("collectionBuilderContracts.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("collectionBuilderContracts.out"), encoding: .utf8)
        try withWorkspace { root in
            let own = try ownStdlibLibrary()
            for runtime in [try m11Runtime(), own.path] {
                let app = try m22Build(root: root, sources: [("hello.kt", source)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: runtime.components(separatedBy: ":"))
                try #require(app.1 == 0, "\(app.2.map(\.message))")
                let result = try java(["-Xverify:all", "-cp", app.0.path + ":" + runtime, "HelloKt"])
                #expect(result.stdout == expected)
                #expect(result.stderr.isEmpty)
            }
        }
    }

    @Test
    func collectionBuilderJavaHelpersAndFrozenViewsMatchKotlin() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMOwnStdlib")
        let expected = try String(contentsOf: fixtures.appendingPathComponent("collectionBuilderViews.out"), encoding: .utf8)
        try withWorkspace { root in
            let own = try ownStdlibLibrary()
            _ = try jvmTool("javac", ["-cp", own.path, fixtures.appendingPathComponent("CollectionBuilderViews.java").path, "-d", root.path], root: root)
            let result = try java(["-Xverify:all", "-cp", root.path + ":" + own.path, "CollectionBuilderViews"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
