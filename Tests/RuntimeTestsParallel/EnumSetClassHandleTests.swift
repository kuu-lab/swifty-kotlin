@testable import Runtime
import Testing

@Suite
struct EnumSetClassHandleTests {
    @Test
    func classLiteralHandlePreservesIdentity() {
        let token = Int(RuntimeTypeTokenEncoding.nominalBase | (123 << RuntimeTypeTokenEncoding.payloadShift))
        runtimeKClassMetadataRegistry.register(typeToken: token, entry: RuntimeKClassMetadataEntry(
            qualifiedName: "EnumSetBridgeEnum", simpleName: "EnumSetBridgeEnum", supertypeDisplayNames: [],
            isDataClass: false, isSealedClass: false, isValueClass: false, isInterface: false,
            isObject: false, isEnumClass: true, isAnnotationClass: false, isAbstract: false,
            fieldCount: 0, memberCount: 0, constructorCount: 0, isFinal: true, isOpen: false,
            visibility: "public", typeParameterCount: 0
        ))
        let handle = __kk_kclass_create(token, 0)
        #expect(__kk_enum_set_class(handle) == handle)
    }

    @Test
    func javaClassHandleRecoversEnumClassifier() throws {
        let enumID: Int64 = 321
        let entry = kk_enum_box_ordinal(1, runtimeMakeStringRaw("TWO"), Int(enumID))
        let javaClass = __kk_any_javaClass(entry)
        #expect(runtimeReleaseObject(entry))
        let handle = __kk_enum_set_class(javaClass)
        let classifier = try #require(runtimeKClassBox(from: handle))
        let expected = (enumID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        #expect(classifier.typeToken == Int(expected))
        #expect(__kk_enum_set_class(javaClass) == handle)
    }

    @Test
    func nonEnumClassifiersAreNotEnumClassHandles() {
        let value = runtimeMakeStringRaw("text")
        #expect(__kk_enum_set_class(__kk_any_javaClass(value)) == runtimeNullSentinelInt)
        #expect(__kk_enum_set_class(__kk_kclass_create(Int(RuntimeTypeTokenEncoding.stringBase), 0)) == runtimeNullSentinelInt)
        let classID = runtimeStableNominalTypeID(fqName: "EnumSetBridgeNonEnum")
        let token = (classID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        let javaClass = registerRuntimeObject(RuntimeJavaClassBox(typeToken: Int(token), displayText: "class TestEnum"))
        #expect(__kk_enum_set_class(javaClass) == runtimeNullSentinelInt)
    }
}
