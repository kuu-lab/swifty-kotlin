#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

/// Swift Testing runs tests on the cooperative pool. Parallel BuildAST used to
/// block those threads on a semaphore while waiting for work queued on
/// `DispatchQueue.global()`. When enough callers blocked at once, GCD started
/// no global workers and every caller waited forever (seen as whole-suite
/// hangs in `buildAndMergeFiles` after #13536 made `jobs` default to cores).
@Suite
struct BuildASTCooperativePoolTests {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var finished = 0
        var errors: [String] = []
    }

    @Test func parallelBuildASTFinishesWhenEveryCooperativeThreadCallsIt() throws {
        let callers = ProcessInfo.processInfo.activeProcessorCount * 2
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var paths: [String] = []
        for index in 0 ..< 24 {
            let url = tempDir.appendingPathComponent("input\(index).kt")
            try "package p\(index)\nfun f\(index)(x: Int): Int = x + \(index)\n".write(to: url, atomically: true, encoding: .utf8)
            paths.append(url.path)
        }
        let inputs = paths
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        for _ in 0 ..< callers {
            Task.detached {
                do {
                    let ctx = makeCompilationContext(inputs: inputs, frontendFlags: ["jobs=4"])
                    try LoadSourcesPhase().run(ctx)
                    try LexPhase().run(ctx)
                    try ParsePhase().run(ctx)
                    try BuildASTPhase().run(ctx)
                } catch {
                    box.lock.withLock { box.errors.append("\(error)") }
                }
                box.lock.withLock { box.finished += 1 }
                done.signal()
            }
        }
        // A kernel timer wakes this wait even when no cooperative thread is free.
        let deadline = DispatchTime.now() + .seconds(120)
        var completed = 0
        while completed < callers, done.wait(timeout: deadline) == .success { completed += 1 }
        box.lock.lock(); defer { box.lock.unlock() }
        #expect(box.finished == callers, "only \(box.finished) of \(callers) BuildAST callers finished")
        #expect(box.errors.isEmpty, "\(box.errors)")
    }
}
#endif
