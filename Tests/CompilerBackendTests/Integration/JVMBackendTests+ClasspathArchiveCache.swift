#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmArchiveCacheUsesContentsAndKeepsCompilationStateLocal() throws {
        try withWorkspace { root in
            let input = root.appendingPathComponent("Library.java")
            let classes = root.appendingPathComponent("classes")
            let dependency = root.appendingPathComponent("dependency.jar")
            let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
            let cache = JVMClasspathArchiveCache()

            func writeDependency(value: Int) throws -> Int {
                let source = "package dep; public class Library { public static final int VALUE = \(value); }"
                try source.write(to: input, atomically: true, encoding: .utf8)
                _ = try javac(["--release", "8", "-d", classes.path, input.path])
                let classFile = try Data(contentsOf: classes.appendingPathComponent("dep/Library.class"))
                let archive = try JVMJarArchive.emit(className: "dep/Library", classFile: classFile, hasMain: false)
                try archive.write(to: dependency, options: .atomic)
                try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: dependency.path)
                return archive.count
            }

            func expectValue(_ expected: Int32, in index: JVMClasspathIndex) throws {
                let type = try #require(index.classes["dep/Library"])
                let field = try #require(type.fields.first { $0.name == "VALUE" })
                guard case let .int(value)? = field.constantValue else {
                    Issue.record("Expected an integer constant")
                    return
                }
                #expect(value == expected)
            }

            let originalSize = try writeDependency(value: 1)
            let first = try JVMClasspathIndex.load([dependency.path], archiveCache: cache)
            try expectValue(1, in: first)
            first.classes.removeValue(forKey: "dep/Library")
            try expectValue(1, in: JVMClasspathIndex.load([dependency.path], archiveCache: cache))

            #expect(try writeDependency(value: 2) == originalSize)
            try expectValue(2, in: JVMClasspathIndex.load([dependency.path], archiveCache: cache))
        }
    }
}
#endif
