#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func parallelClasspathReportsFirstSortedClassError() throws {
        try withWorkspace { root in
            let malformed = Data([0xCA, 0xFE, 0xBA, 0xBE])
            let entries = (0 ..< 128).reversed().map { ("dep/A\($0).class", malformed) }
            let archive = try JVMJarArchive.emit(className: "dep/Z", classFile: malformed, classes: entries)
            let dependency = root.appendingPathComponent("malformed.jar")
            try archive.write(to: dependency)

            for jobs in [1, 4] {
                do {
                    _ = try JVMClasspathIndex.load([dependency.path], archiveJobs: jobs)
                    Issue.record("Expected malformed classfile to fail with \(jobs) workers")
                } catch let error as JVMFrontendError {
                    #expect(error.message.hasPrefix("Cannot read JVM class dep/A0.class at offset"))
                }
            }
        }
    }
}
#endif
