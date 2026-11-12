#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importsModifiedUTF8StringConstants() throws {
        try withWorkspace { root in
            let source = #"""
            package dep;
            public class Text {
                public static final String ASCII = "constant";
                public static final String EMPTY = "";
                public static final String MIXED = "a\0é😀";
            }
            """#
            let input = root.appendingPathComponent("Text.java")
            let classes = root.appendingPathComponent("classes")
            try source.write(to: input, atomically: true, encoding: .utf8)
            _ = try javac(["--release", "8", "-encoding", "UTF-8", "-d", classes.path, input.path])
            let index = try JVMClasspathIndex.load([classes.path])
            let info = try #require(index.classes["dep/Text"])
            let strings = info.fields.reduce(into: [String: String]()) { result, field in
                if case let .string(value)? = field.constantValue {
                    result[field.name] = value
                }
            }
            #expect(strings == ["ASCII": "constant", "EMPTY": "", "MIXED": "a\u{0}é😀"])
        }
    }
}
#endif
