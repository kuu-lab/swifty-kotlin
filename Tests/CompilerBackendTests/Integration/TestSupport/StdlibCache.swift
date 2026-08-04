@testable import CompilerCore
@testable import CompilerBackend
import Foundation

private enum TestStdlibCacheError: Error, CustomStringConvertible {
    case artifactMissing(String)

    var description: String {
        switch self {
        case .artifactMissing(let path):
            return "Shared stdlib artifact was not produced at \(path)"
        }
    }
}

/// Builds a single shared bundled-stdlib `.kklib` once per test process and
/// publishes it through ``CompilerOptions/defaultStdlibLibraryPath`` so that
/// every test that asks for bundled stdlib can reuse the precompiled artifact
/// instead of recompiling the frontend-to-KIR pipeline.
final class TestStdlibCache: @unchecked Sendable {
    static let shared = TestStdlibCache()

    private let lock = NSRecursiveLock()
    private var didPrepare = false

    func prepare() {
        lock.lock()
        defer { lock.unlock() }

        guard !didPrepare else { return }
        didPrepare = true

        do {
            let path = try build()
            CompilerOptions.defaultStdlibLibraryPath = path
        } catch {
            let message = "[TestStdlibCache] Failed to build shared stdlib artifact: \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    private func build() throws -> String {
        let artifactBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-test-stdlib-cache-\(UUID().uuidString)")
            .path

        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: artifactBase,
            includeStdlib: true,
            stdlibOnly: true
        )

        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        let artifactPath = artifactBase + ".kklib"
        let fm = FileManager.default
        guard fm.fileExists(atPath: artifactPath) else {
            throw TestStdlibCacheError.artifactMissing(artifactPath)
        }

        return artifactPath
    }
}

