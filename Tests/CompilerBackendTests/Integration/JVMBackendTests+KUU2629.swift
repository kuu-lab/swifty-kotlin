#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kuu2629SegmentPrivateConstructorPublicSyntheticBridge() throws {
        try withWorkspace { root in
            let library = try m22Build(root: root, name: "stdlib.jar", stdlib: true)
            try #require(library.1 == 0, "stdlib build failed: \(library.2.map(\.message))")

            let support = try repositoryFileSource("Tests/CompilerBackendTests/Fixtures/KUU-2629/JVMRuntimeSupport.kt", file: #filePath)
            let segment = try repositoryFileSource("Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt", file: #filePath)
            let pool = try repositoryFileSource("Sources/CompilerCore/Stdlib/kotlinx/io/SegmentPool.kt", file: #filePath)
            let output = try m22Build(
                root: root,
                sources: [("JVMRuntimeSupport.kt", support), ("Segment.kt", segment), ("SegmentPool.kt", pool)],
                name: "classes",
                mode: .jvmClass,
                classpath: [library.0.path]
            )
            try #require(output.1 == 0, "Segment classfile generation failed: \(output.2.map(\.message))")

            let probeSource = try repositoryFileSource("Tests/CompilerBackendTests/Fixtures/KUU-2629/SegmentBridgeProbe.java", file: #filePath)
            let probeFile = root.appendingPathComponent("SegmentBridgeProbe.java")
            try probeSource.write(to: probeFile, atomically: true, encoding: .utf8)
            let classpath = output.0.path + ":" + library.0.path
            _ = try jvmTool("javac", ["-cp", classpath, "-d", root.path, probeFile.path], root: root)

            let execution = try java(["-cp", root.path + ":" + classpath, "SegmentBridgeProbe"])
            #expect(execution.stdout == "public synthetic bridge invoked; private constructor retained; writeTo copied bytes\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
