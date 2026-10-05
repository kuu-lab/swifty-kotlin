@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeKClassStringTests {
    private func checkRenderers(_ raw: Int, expected: String) {
        #expect(runtimeElementToString(raw) == expected)
        #expect(runtimeRenderAnyForPrint(raw) == expected)
        #expect(extractString(from: kk_any_to_string(raw, 0)) == expected)
        let list = registerRuntimeObject(RuntimeListBox(elements: [raw]))
        #expect(runtimeElementToString(list) == "[\(expected)]")
        #expect(runtimeRenderAnyForPrint(list) == "[\(expected)]")
    }

    @Test func nameHintRendersUnregisteredClass() {
        let raw = __kk_kclass_create(0x1080_0000, runtimeMakeStringRaw("Annotated"))
        checkRenderers(raw, expected: "class Annotated")
    }

    @Test func metadataQualifiedNameTakesPrecedenceOverSimpleHint() {
        let token = 0x1080_0200
        _ = __kk_kclass_register_metadata(
            token, runtimeMakeStringRaw("sample.Annotated"),
            runtimeMakeStringRaw("Annotated"), 0, 0, 0, 0, 0
        )
        let raw = __kk_kclass_create(token, runtimeMakeStringRaw("Annotated"))
        checkRenderers(raw, expected: "class sample.Annotated")
    }

    @Test func nestedDisplayNamePreservesReflectionNames() {
        let token = 0x1262_0200
        _ = __kk_kclass_register_metadata(
            token, runtimeMakeStringRaw("Sample.lower.nested"),
            runtimeMakeStringRaw("nested"), 0, 0, 0, 0, 0
        )
        let raw = __kk_kclass_create(token, runtimeMakeStringRaw("nested"))
        _ = __kk_kclass_register_display_name(token, runtimeMakeStringRaw("Sample.lower$nested"))
        checkRenderers(raw, expected: "class Sample.lower$nested")
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_kclass_qualified_name(raw))) == "Sample.lower.nested")
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_kclass_simple_name(raw))) == "nested")
    }

    @Test func builtinClassUsesQualifiedName() {
        checkRenderers(__kk_kclass_create(15, 0), expected: "class kotlin.Unit")
    }
}
