#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// Smallest classfile `JVMClassReader` accepts: ACC_PUBLIC|ACC_SUPER,
    /// superclass java/lang/Object, empty constant-pool members.
    private static func minimalClass(named name: String) -> Data {
        let utf8 = Array(name.utf8)
        let object = Array("java/lang/Object".utf8)
        var bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 45, 0, 5]
        bytes += [1, UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8
        bytes += [7, 0, 1]
        bytes += [1, UInt8(object.count >> 8), UInt8(object.count & 0xFF)] + object
        bytes += [7, 0, 3]
        bytes += [0, 0x21, 0, 2, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0]
        return Data(bytes)
    }

    @Test
    func parallelClasspathIndexesEverySortedClass() throws {
        try withWorkspace { root in
            // 385 entries split into seven 64-entry batches, so workers each
            // drain more than one batch and results must be reassembled in
            // entry order.
            let entries = (0 ..< 384).map { ("dep/A\($0).class", Self.minimalClass(named: "dep/A\($0)")) }
            let archive = try JVMJarArchive.emit(className: "dep/Z", classFile: Self.minimalClass(named: "dep/Z"), classes: entries)
            let dependency = root.appendingPathComponent("classes.jar")
            try archive.write(to: dependency)
            let shadow = try JVMJarArchive.emit(
                className: "dep/B0",
                classFile: Self.minimalClass(named: "dep/B0"),
                classes: [("dep/A0.class", Self.minimalClass(named: "dep/A0")), ("dep/B1.class", Self.minimalClass(named: "dep/B1"))]
            )
            let shadowPath = root.appendingPathComponent("shadow.jar")
            try shadow.write(to: shadowPath)

            for jobs in [1, 4] {
                let index = try JVMClasspathIndex.load([dependency.path, shadowPath.path], archiveJobs: jobs)
                #expect(index.classes.count == 387)
                #expect(index.classes["dep/A0"] != nil)
                #expect(index.classes["dep/A383"] != nil)
                #expect(index.classes["dep/Z"] != nil)
                #expect(index.classes["dep/B0"] != nil)
                #expect(index.classes["dep/B1"] != nil)
            }
        }
    }

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
