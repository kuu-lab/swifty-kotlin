#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    func m22Build(root: URL, sources: [(String, String)] = [], name: String, mode: EmitMode = .jvmJar, stdlib: Bool = false, classpath: [String] = []) throws -> (URL, Int, [Diagnostic]) {
        var inputs: [String] = []
        for (name, source) in sources {
            let path = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: path, atomically: true, encoding: .utf8)
            inputs.append(path.path)
        }
        let output = root.appendingPathComponent(name)
        let options = CompilerOptions(moduleName: "M22", inputs: inputs, outputPath: output.path, emit: mode, target: .hostDefault(), stdlibOnly: stdlib, jvmClasspath: classpath)
        let result = CompilerDriver(backendPhases: makeBackendPhases).runForTesting(options: options)
        return (output, result.exitCode, result.diagnostics)
    }

}
#endif
