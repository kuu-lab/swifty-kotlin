#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func classReaderIndexesKotlinDefaultArgumentMethodsSeparately() throws {
        try withWorkspace { root in
            try """
            package fixture
            fun label(value: String = "task"): String = value
            """.write(to: root.appendingPathComponent("Foreign.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Foreign.kt", "-d", "foreign"], root: root)
            let file = root.appendingPathComponent("foreign/fixture/ForeignKt.class")
            var reader = JVMClassReader(bytes: Array(try Data(contentsOf: file)))
            let info = try reader.read()
            #expect(info.methods.contains { $0.name == "label" })
            #expect(!info.methods.contains { $0.name == "label$default" })
            let method = try #require(info.defaultArgumentMethods.first)
            #expect(method.name == "label$default")
            #expect(method.descriptor == "(Ljava/lang/String;ILjava/lang/Object;)Ljava/lang/String;")
            #expect(method.isStatic)
        }
    }
}
#endif
