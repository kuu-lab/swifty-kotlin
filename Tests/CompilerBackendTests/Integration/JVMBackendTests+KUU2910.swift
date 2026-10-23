#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionMemberDispatchGaps(mode: EmitMode) throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/JVMOwnStdlib")
        let source = try String(contentsOf: fixtures.appendingPathComponent("collectionMemberDispatchGaps.kt"), encoding: .utf8)
        let expected = try String(contentsOf: fixtures.appendingPathComponent("collectionMemberDispatchGaps.out"), encoding: .utf8)
        try withWorkspace { root in
            try runRuntimeParity(source, expected: expected, mode: mode, root: root)
            let sequenceSource = try String(contentsOf: fixtures.appendingPathComponent("sequenceAggregateDispatch.kt"), encoding: .utf8)
            let sequenceExpected = try String(contentsOf: fixtures.appendingPathComponent("sequenceAggregateDispatch.out"), encoding: .utf8)
            let runtimes = [try m11Runtime(), try ownStdlibLibrary().path]
            for (index, runtime) in runtimes.enumerated() {
                let name = index == 0 ? "sequence-official" : "sequence-own"
                let app = try m22Build(
                    root: root,
                    sources: [("sequence.kt", sequenceSource)],
                    name: name + (mode == .jvmJar ? ".jar" : "classes"),
                    mode: mode,
                    classpath: runtime.components(separatedBy: ":")
                )
                try #require(app.1 == 0, "\(app.2.map(\.message))")
                let result = try java(["-cp", app.0.path + ":" + runtime, "SequenceKt"])
                #expect(result.stdout == sequenceExpected)
                #expect(result.stderr.isEmpty)
            }
        }
    }
}
#endif
