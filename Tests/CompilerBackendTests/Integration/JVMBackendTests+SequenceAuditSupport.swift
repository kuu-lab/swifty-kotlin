#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

enum JVMSequenceAuditLane: CaseIterable, Equatable, Sendable {
    case candidateClass
    case candidateJar
    case officialProducer
}

private final class JVMSequenceAuditStdlibCache: @unchecked Sendable {
    static let shared = JVMSequenceAuditStdlibCache()
    private let lock = NSLock()
    private var artifact: URL?

    func library() throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        if let artifact { return artifact }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kswiftk-sequence-audit-stdlib-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("kswiftk-stdlib.jar")
        let options = CompilerOptions(moduleName: "SequenceAuditStdlib", inputs: [], outputPath: output.path, emit: .jvmJar, target: .hostDefault(), stdlibOnly: true)
        let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
        try #require(result.exitCode == 0, "\(result.diagnostics.map(\.message))")
        artifact = output
        return output
    }
}

extension JVMBackendTests {
    func runSequenceAuditFixture(_ name: String, lane: JVMSequenceAuditLane) throws {
        let library = try JVMSequenceAuditStdlibCache.shared.library()
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/JVMSequenceAudit")
        let source = try String(contentsOf: fixtures.appendingPathComponent(name + ".kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent(name + ".out"), encoding: .utf8)
        try withWorkspace { root in
            let artifact: URL
            switch lane {
            case .candidateClass, .candidateJar:
                let mode: EmitMode = lane == .candidateClass ? .jvmClass : .jvmJar
                let app = try m22Build(root: root, sources: [("hello.kt", source)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.path])
                try #require(app.1 == 0, "\(app.2.map(\.message))")
                artifact = app.0
            case .officialProducer:
                try source.write(to: root.appendingPathComponent("hello.kt"), atomically: true, encoding: .utf8)
                _ = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
                artifact = root.appendingPathComponent("reference.jar")
                let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + m11Runtime(), "HelloKt"])
                #expect(reference.stdout == expected)
                #expect(reference.stderr.isEmpty)
            }
            let result = try java(["-Xverify:all", "-cp", artifact.path + ":" + library.path, "HelloKt"])
            #expect(result.stdout == expected)
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
