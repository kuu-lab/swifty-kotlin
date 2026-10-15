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

    @Test func kClassJavaMappingPreservesRepresentedClassifier() {
        let kclass = __kk_kclass_create(0x123406, runtimeMakeStringRaw("test.Sample"))
        let javaClass = __kk_any_javaClass(kclass)

        #expect(runtimeObjectTypeID(rawValue: javaClass) == runtimeStableNominalTypeID(fqName: "java.lang.Class"))
        #expect(__kk_class_kotlin(javaClass) == kclass)
    }

    @Test func javaClassDeclaredConstructorsReturnsRegisteredHandles() {
        let kclass = __kk_kclass_create(0x123407, runtimeMakeStringRaw("test.Sample"))
        let constructor = __kk_kconstructor_create(
            runtimeMakeStringRaw("<init>"),
            0,
            runtimeMakeStringRaw("test.Sample"),
            0,
            1,
            runtimeMakeStringRaw("PUBLIC"),
            kclass
        )
        let javaClass = __kk_any_javaClass(kclass)
        let constructors = __kk_class_declared_constructors(javaClass)

        #expect(runtimeArrayBox(from: constructors)?.elements == [constructor])
    }

    @Test func javaClassDeclaredConstructorMatchesParameterTypeTokens() {
        let kclass = __kk_kclass_create(0x123408, runtimeMakeStringRaw("test.Sample"))
        let intConstructor = __kk_kconstructor_create(
            runtimeMakeStringRaw("<init>"), 1, runtimeMakeStringRaw("test.Sample"), 0, 0,
            runtimeMakeStringRaw("PUBLIC"), kclass
        )
        let stringConstructor = __kk_kconstructor_create(
            runtimeMakeStringRaw("<init>"), 1, runtimeMakeStringRaw("test.Sample"), 0, 1,
            runtimeMakeStringRaw("PUBLIC"), kclass
        )
        #expect(__kk_kconstructor_set_parameter_type(intConstructor, 0, 3) == 1)
        #expect(__kk_kconstructor_set_parameter_type(stringConstructor, 0, 2) == 1)

        let javaClass = __kk_any_javaClass(kclass)
        let stringClass = __kk_any_javaClass(__kk_kclass_create(2, 0))
        let parameterTypes = RuntimeArrayBox(length: 1)
        parameterTypes[0] = stringClass
        let parameterTypesRaw = registerRuntimeObject(parameterTypes)

        #expect(__kk_class_declared_constructor(javaClass, parameterTypesRaw) == stringConstructor)
    }
}
