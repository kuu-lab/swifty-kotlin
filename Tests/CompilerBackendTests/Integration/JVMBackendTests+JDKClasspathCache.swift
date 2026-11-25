#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jdkClasspathCacheTracksSelectionAndInPlaceImageChanges() throws {
        try withWorkspace { root in
            let image = root.appendingPathComponent("modules")
            let tool = root.appendingPathComponent("jimage")
            try Data([1]).write(to: image)
            try Data([0]).write(to: tool)
            let date = try #require(image.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            let store = ContentAddressedStore(rootPath: root.appendingPathComponent("cache").path)
            var extractions = 0

            func read(_ pattern: String) throws -> Data {
                let files = try JVMJDKClasspathCache.load(image: image, jimage: tool, patterns: [pattern], store: store) {
                    extractions += 1
                    return [.init(path: "java/lang/Object.class", contents: try Data(contentsOf: image))]
                }
                return try #require(files.first?.contents)
            }

            #expect(try read("glob:**/java/lang/*.class") == Data([1]))
            #expect(try read("glob:**/java/lang/*.class") == Data([1]))
            #expect(extractions == 1)
            #expect(try read("glob:**/java/util/*.class") == Data([1]))
            #expect(extractions == 2)

            let handle = try FileHandle(forWritingTo: image)
            try handle.write(contentsOf: Data([2]))
            try handle.close()
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: image.path)
            #expect(try read("glob:**/java/lang/*.class") == Data([2]))
            #expect(extractions == 3)
        }
    }

    // Backtick-escaped segments (mandatory for keyword package parts such as
    // `annotation`) must still register the referenced JDK packages.
    @Test
    func jdkClasspathImportScanSeesThroughBacktickedSegments() throws {
        let source = """
        package com.example.`annotation`

        import javax.`annotation`.processing.Generated
        import java.`util`.Objects
        import java.`util`.*
        """
        let paths = JVMJDKClasspath.importedPaths(in: source)
        #expect(paths.contains("com.example.`annotation`"))
        #expect(paths.contains("javax.`annotation`.processing.Generated"))
        #expect(paths.contains("java.`util`.Objects"))
        #expect(paths.contains("java.`util`.*"))
    }
}
#endif
