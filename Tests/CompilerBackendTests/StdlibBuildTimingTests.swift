@testable import CompilerBackend
import Dispatch
import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite
struct StdlibBuildTimingTests {
    @Test
    func recordsConcurrentStartsAndEndsWithoutLosingEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("timings.jsonl").path

        DispatchQueue.concurrentPerform(iterations: 24) { index in
            let timing = StdlibBuildTiming.start(kind: "test", path: path)
            timing?.finish(success: index % 2 == 0)
        }

        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let records = try contents.split(separator: "\n").map { line in
            let data = Data(line.utf8)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        #expect(records.count == 48)
        let starts = records.filter { $0["event"] as? String == "start" }
        let ends = records.filter { $0["event"] as? String == "end" }
        #expect(starts.count == 24)
        #expect(ends.count == 24)
        #expect(Set(starts.compactMap { $0["id"] as? String }) == Set(ends.compactMap { $0["id"] as? String }))
        #expect(ends.filter { $0["success"] as? Bool == true }.count == 12)
        #expect(ends.allSatisfy { ($0["elapsed_seconds"] as? Double ?? -1) >= 0 })
    }

    @Test
    func disabledOrUnwritableTimingsDoNotPreventTheBuild() throws {
        #expect(StdlibBuildTiming.start(kind: "test", path: nil) == nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let timing = try #require(StdlibBuildTiming.start(kind: "test", path: directory.path))
        timing.finish(success: false)
        let fifo = directory.appendingPathComponent("fifo").path
        #expect(mkfifo(fifo, 0o600) == 0)
        StdlibBuildTiming.start(kind: "test", path: fifo)?.finish(success: false)
    }
}
