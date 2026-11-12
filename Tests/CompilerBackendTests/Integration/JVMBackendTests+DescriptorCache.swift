#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func cachedDescriptorsPreserveASCIIValidation() throws {
        let cache = JVMDescriptorCache()
        let ascii = "()Ldep/K;"
        let unicode = "()Ldep/\u{212A};"
        #expect(ascii == unicode)
        let (_, result) = try cache.parse(ascii)
        #expect(result.referenceName == "dep/K")
        #expect(throws: JVMClassReader.Invalid.self) {
            _ = try cache.parse(unicode)
        }
    }
}
#endif
