#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeFunctionStringTests {
    @Test func absentInlineFunctionMetadataDoesNotChangeZeroRendering() {
        let source = 0x1081_003
        defer { removeRuntimeObjectMetadata(forObjectKey: UInt(bitPattern: source)) }
        let text = Int(bitPattern: runtimeMakeStringPointer("kotlin.Function1"))
        __kk_function_set_description(0, text, 1)
        #expect(runtimeFunctionDescription(0) == nil)
        #expect(runtimeElementToString(0) == "0")
        __kk_function_set_description(source, text, 1)
        __kk_function_copy_description(source, 0)
        #expect(runtimeFunctionDescription(0) == nil)
        #expect(runtimeElementToString(0) == "0")
        #expect(runtimeElementToString(source) == "kotlin.Function1@1081003")
    }

    @Test func rawFunctionUsesRegisteredSignatureInAllRenderers() {
        let raw = 0x1081_001
        defer { removeRuntimeObjectMetadata(forObjectKey: UInt(bitPattern: raw)) }
        let text = "fun top(): kotlin.Int"
        __kk_function_set_description(raw, Int(bitPattern: runtimeMakeStringPointer(text)), 0)
        #expect(runtimeElementToString(raw) == text)
        #expect(extractString(from: kk_any_to_string(raw, 0)) == text)
        let list = registerRuntimeObject(RuntimeListBox(elements: [raw]))
        #expect(runtimeElementToString(list) == "[\(text)]")
    }

    @Test func lambdaIdentityIsNonemptyAndStable() {
        let raw = 0x1081_002
        defer { removeRuntimeObjectMetadata(forObjectKey: UInt(bitPattern: raw)) }
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

    @Test func erasedBoundaryWrapperPreservesSignatureAndIdentity() {
        let source = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 1, closureRaw: 0, arity: 0))
        let wrapper = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 2, closureRaw: 0, arity: 0))
        __kk_function_copy_description(source, wrapper)
        #expect(runtimeElementToString(wrapper) == runtimeElementToString(source))
        let text = "fun top(): kotlin.Int"
        __kk_function_set_description(source, Int(bitPattern: runtimeMakeStringPointer(text)), 0)
        __kk_function_copy_description(source, wrapper)
        #expect(runtimeElementToString(wrapper) == text)
    }

    @Test func objectMetadataRemovalClearsFunctionDescription() {
        let raw = registerRuntimeObject(RuntimeFunctionValueBox(fnPtr: 1, closureRaw: 0, arity: 1))
        __kk_function_set_description(raw, Int(bitPattern: runtimeMakeStringPointer("fun f(): kotlin.Int")), 0)
        #expect(runtimeElementToString(raw) == "fun f(): kotlin.Int")
        removeRuntimeObjectMetadata(forObjectKey: UInt(bitPattern: raw))
        #expect(runtimeElementToString(raw).hasPrefix("kotlin.Function1@"))
    }

    // KUU-3947: accessor-backed KProperty wrappers are plain object boxes —
    // without a description println rendered `<object 0x…>`; the pinned
    // `val pkg.Owner.name: kotlin.T` text must win instead.
    @Test func propertyRefWrapperPrintsCompilerDescription() {
        let raw = kk_object_new(1, 0x51_44)
        defer { removeRuntimeObjectMetadata(forObjectKey: UInt(bitPattern: raw)) }
        _ = kk_callable_ref_tag_kproperty(
            raw,
            runtimeMakeStringRaw("prop"),
            runtimeMakeStringRaw("kotlin.Int"),
            1
        )
        #expect(runtimeRenderAnyForPrint(raw).hasPrefix("<object "))
        let text = "val pkg.C.prop: kotlin.Int"
        __kk_function_set_description(raw, runtimeMakeStringRaw(text), 0)
        #expect(runtimeRenderAnyForPrint(raw) == text)
        #expect(extractString(from: kk_any_to_string(raw, 0)) == text)
    }
}
#endif
