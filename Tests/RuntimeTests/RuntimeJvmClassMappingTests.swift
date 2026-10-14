@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeJvmClassMappingTests {
    @Test func primitiveRoundTripAndIdentity() {
        for token in [3, 4, 11, 12, 13, 14, 16, 17] {
            let kclass = __kk_kclass_create(token, 0)
            let javaClass = __kk_kclass_java_primitive_type(kclass)
            #expect(javaClass != runtimeNullSentinelInt)
            #expect(runtimeObjectTypeID(rawValue: javaClass) == runtimeStableNominalTypeID(fqName: "java.lang.Class"))
            #expect(__kk_class_kotlin(javaClass) == kclass)
            #expect(__kk_kclass_java_primitive_type(kclass) == javaClass)
        }
    }

    @Test func nonPrimitiveTypesReturnNull() {
        for token in [1, 2, 7, 8, 9, 10, 15, 18, 0x123406] {
            #expect(__kk_kclass_java_primitive_type(__kk_kclass_create(token, 0)) == runtimeNullSentinelInt)
        }
    }

    @Test func nothingMapsToJvmVoid() {
        let kclass = __kk_kclass_create(0, runtimeMakeStringRaw("java.lang.Void"))
        let javaClass = __kk_kclass_java_primitive_type(kclass)
        #expect(javaClass != runtimeNullSentinelInt)
        #expect(__kk_class_kotlin(javaClass) == kclass)
    }

    @Test func objectJavaClassMapsToItsRuntimeClassifier() {
        let value = runtimeMakeStringRaw("value")
        let javaClass = __kk_any_javaClass(value)
        _ = runtimeReleaseObject(value)
        #expect(__kk_class_kotlin(javaClass) == __kk_kclass_create(2, 0))
        #expect(__kk_class_kotlin(__kk_any_javaClass(kk_box_int(42))) == __kk_kclass_create(3, 0))
    }
}
