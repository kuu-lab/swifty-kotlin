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

    @Test func javaObjectTypeUsesPrimitiveWrappersAndIsInterned() {
        let cases: [(Int, String)] = [
            (Int(RuntimeTypeTokenEncoding.booleanBase), "java.lang.Boolean"),
            (Int(RuntimeTypeTokenEncoding.byteBase), "java.lang.Byte"),
            (Int(RuntimeTypeTokenEncoding.shortBase), "java.lang.Short"),
            (Int(RuntimeTypeTokenEncoding.intBase), "java.lang.Integer"),
            (Int(RuntimeTypeTokenEncoding.longBase), "java.lang.Long"),
            (Int(RuntimeTypeTokenEncoding.charBase), "java.lang.Character"),
            (Int(RuntimeTypeTokenEncoding.floatBase), "java.lang.Float"),
            (Int(RuntimeTypeTokenEncoding.doubleBase), "java.lang.Double"),
        ]
        for (token, expectedName) in cases {
            let kclass = __kk_kclass_create(token, 0)
            let javaClass = __kk_kclass_java_object_type(kclass)
            #expect(javaClass != __kk_kclass_java_class(kclass))
            #expect(__kk_kclass_java_object_type(kclass) == javaClass)
            #expect(__kk_class_kotlin(javaClass) == kclass)
            #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_get_name(javaClass))) == expectedName)
            #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_canonical_name(javaClass))) == expectedName)
            #expect(runtimeJavaClassToStringText(javaClass) == "class \(expectedName)")
        }
    }

    @Test func javaObjectTypePreservesReferenceClassHandle() {
        let kclass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.stringBase), 0)
        #expect(__kk_kclass_java_object_type(kclass) == __kk_kclass_java_class(kclass))
    }

    @Test func nothingJavaObjectTypeUsesJavaVoidClass() {
        let kclass = __kk_kclass_create(0, runtimeMakeStringRaw("kotlin.Nothing"))
        let javaClass = __kk_kclass_java_object_type(kclass)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_canonical_name(javaClass))) == "java.lang.Void")
        #expect(__kk_class_kotlin(javaClass) == kclass)
    }

    @Test func objectJavaClassMapsToItsRuntimeClassifier() {
        let value = runtimeMakeStringRaw("value")
        let javaClass = __kk_any_javaClass(value)
        _ = runtimeReleaseObject(value)
        #expect(__kk_class_kotlin(javaClass) == __kk_kclass_create(2, 0))
        #expect(__kk_class_kotlin(__kk_any_javaClass(kk_box_int(42))) == __kk_kclass_create(3, 0))
    }

    @Test func javaClassHandlesShareConcreteCollectionAndArrayTypes() {
        let twoElementListA = registerRuntimeObject(
            RuntimeListBox(elements: [kk_box_int(1), kk_box_int(2)]),
            typeID: listRuntimeTypeID
        )
        let twoElementListB = registerRuntimeObject(
            RuntimeListBox(elements: [kk_box_int(3), kk_box_int(4)]),
            typeID: listRuntimeTypeID
        )
        let oneElementList = registerRuntimeObject(
            RuntimeListBox(elements: [kk_box_int(5)]),
            typeID: listRuntimeTypeID
        )
        let twoElementListClassA = __kk_any_javaClass(twoElementListA)
        let twoElementListClassB = __kk_any_javaClass(twoElementListB)
        let oneElementListClass = __kk_any_javaClass(oneElementList)
        #expect(twoElementListClassA == twoElementListClassB)
        #expect(twoElementListClassA != oneElementListClass)

        let arrayTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Array")
        func genericArray(componentToken: Int) -> Int {
            let array = kk_array_new(1)
            _ = kk_array_tag_type(array, Int(truncatingIfNeeded: arrayTypeID))
            let component = __kk_array_component_type(componentToken, 0)
            _ = __kk_array_tag_component(array, component)
            return array
        }
        let stringArrayA = genericArray(componentToken: Int(RuntimeTypeTokenEncoding.stringBase))
        let stringArrayB = genericArray(componentToken: Int(RuntimeTypeTokenEncoding.stringBase))
        let intArray = genericArray(componentToken: Int(RuntimeTypeTokenEncoding.intBase))
        let stringArrayClassA = __kk_any_javaClass(stringArrayA)
        let stringArrayClassB = __kk_any_javaClass(stringArrayB)
        let intArrayClass = __kk_any_javaClass(intArray)
        #expect(stringArrayClassA == stringArrayClassB)
        #expect(stringArrayClassA != intArrayClass)
    }

    @Test func kClassJavaMappingPreservesRepresentedClassifier() {
        let kclass = __kk_kclass_create(0x123406, runtimeMakeStringRaw("test.Sample"))
        let javaClass = __kk_any_javaClass(kclass)

        #expect(runtimeObjectTypeID(rawValue: javaClass) == runtimeStableNominalTypeID(fqName: "java.lang.Class"))
        #expect(__kk_class_kotlin(javaClass) == kclass)
    }

    @Test func javaClassDeclaredConstructorsReturnsRegisteredConstructorWrappers() throws {
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

        let constructorHandles = try #require(runtimeArrayBox(from: constructors)?.elements)
        #expect(constructorHandles.count == 1)
        let constructorHandle = try #require(constructorHandles.first)
        let constructorWrapper = try #require(
            resolveRuntimeHandle(constructorHandle, as: RuntimeJavaConstructorBox.self)
        )
        #expect(constructorWrapper.callableRaw == constructor)
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

        let reflectedConstructor = __kk_class_declared_constructor(javaClass, parameterTypesRaw)
        #expect(
            resolveRuntimeHandle(reflectedConstructor, as: RuntimeJavaConstructorBox.self)?.callableRaw
                == stringConstructor
        )
    }

    @Test func lambdaJavaClassRetainsItsEnclosingFileFacade() {
        let functionPointer = 0x12345
        let className = runtimeMakeStringRaw("LambdaInPackageKt")
        __kk_function_set_enclosing_class(functionPointer, className)

        let functionValue = kk_function_create_0(functionPointer, 0, nil)
        let javaClass = __kk_any_javaClass(functionValue)
        let enclosingClass = __kk_class_get_enclosing_class(javaClass)

        #expect(enclosingClass != runtimeNullSentinelInt)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_get_name(enclosingClass))) == "LambdaInPackageKt")
        #expect(__kk_class_get_enclosing_class(enclosingClass) == runtimeNullSentinelInt)

        _ = runtimeReleaseObject(javaClass)
        _ = runtimeReleaseObject(enclosingClass)
        _ = runtimeReleaseObject(functionValue)
    }

    @Test func javaClassToStringUsesJvmNameAndKeepsKClassRendering() {
        let value = runtimeMakeStringRaw("value")
        let javaClass = __kk_any_javaClass(value)
        _ = runtimeReleaseObject(value)

        #expect(runtimeJavaClassToStringText(javaClass) == "class java.lang.String")
        #expect(runtimeRenderAnyForPrint(javaClass) == "class java.lang.String")
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_toString(javaClass))) == "class java.lang.String")
        #expect(runtimeRenderAnyForPrint(__kk_class_kotlin(javaClass)) == "class kotlin.String")
    }

    @Test func arrayKClassToStringKeepsKotlinQualifiedName() {
        let name = "kotlin.IntArray"
        let typeToken = runtimeNominalTypeToken(runtimeStableNominalTypeID(fqName: name))
        let kclass = RuntimeKClassBox(typeToken: typeToken, nameHint: runtimeMakeStringRaw(name))
        #expect(runtimeKClassToString(kclass) == "class kotlin.IntArray")
    }

    @Test func javaClassToStringRecognizesRuntimeCollectionImplementations() {
        let elements = [kk_box_int(1), kk_box_int(7), kk_box_int(53)]
        let set = registerRuntimeObject(RuntimeSetBox(elements: elements))
        let list = registerRuntimeObject(RuntimeListBox(elements: elements))
        let map = registerRuntimeObject(RuntimeMapBox(keys: elements, values: elements))
        defer {
            _ = runtimeReleaseObject(set)
            _ = runtimeReleaseObject(list)
            _ = runtimeReleaseObject(map)
        }

        let setClass = __kk_any_javaClass(set)
        let listClass = __kk_any_javaClass(list)
        let mapClass = __kk_any_javaClass(map)
        defer {
            _ = runtimeReleaseObject(setClass)
            _ = runtimeReleaseObject(listClass)
            _ = runtimeReleaseObject(mapClass)
        }

        #expect(runtimeJavaClassToStringText(setClass) == "class java.util.LinkedHashSet")
        #expect(runtimeJavaClassToStringText(listClass) == "class java.util.Arrays$ArrayList")
        #expect(runtimeJavaClassToStringText(mapClass) == "class java.util.LinkedHashMap")
    }

    @Test func primitiveJavaClassToStringUsesPrimitiveNames() {
        let cases: [(Int, String)] = [
            (Int(RuntimeTypeTokenEncoding.booleanBase), "boolean"),
            (Int(RuntimeTypeTokenEncoding.byteBase), "byte"),
            (Int(RuntimeTypeTokenEncoding.shortBase), "short"),
            (Int(RuntimeTypeTokenEncoding.intBase), "int"),
            (Int(RuntimeTypeTokenEncoding.longBase), "long"),
            (Int(RuntimeTypeTokenEncoding.charBase), "char"),
            (Int(RuntimeTypeTokenEncoding.floatBase), "float"),
            (Int(RuntimeTypeTokenEncoding.doubleBase), "double"),
            (Int(RuntimeTypeTokenEncoding.nullBase), "void"),
        ]
        for (token, expected) in cases {
            let javaClass = __kk_kclass_java_primitive_type(__kk_kclass_create(token, 0))
            #expect(runtimeJavaClassToStringText(javaClass) == expected)
            #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_class_toString(javaClass))) == expected)
        }
    }
}
