#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeFunctionStringTests {
    @Test func rawFunctionUsesRegisteredSignatureInAllRenderers() {
        let raw = 0x1081_001
        let text = "fun top(): kotlin.Int"
        __kk_function_set_description(raw, Int(bitPattern: runtimeMakeStringPointer(text)), 0)
        #expect(runtimeElementToString(raw) == text)
        #expect(extractString(from: kk_any_to_string(raw, 0)) == text)
        let list = registerRuntimeObject(RuntimeListBox(elements: [raw]))
        #expect(runtimeElementToString(list) == "[\(text)]")
    }

    @Test func lambdaIdentityIsNonemptyAndStable() {
        let raw = 0x1081_002
        __kk_function_set_description(raw, Int(bitPattern: runtimeMakeStringPointer("kotlin.Function0")), 1)
        let text = runtimeElementToString(raw)
        #expect(text == "kotlin.Function0@1081002")
        #expect(extractString(from: kk_any_to_string(raw, 0)) == text)
    }

    @Test func capturingFunctionBoxUsesIdentityWithoutCompilerMetadata() {
        let raw = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 1, closureRaw: 0, arity: 2))
        #expect(runtimeElementToString(raw).hasPrefix("kotlin.Function2@"))
        #expect(runtimeElementToString(7) == "7")
        #expect(runtimeElementToString(runtimeNullSentinelInt) == "null")
    }
}
#endif
