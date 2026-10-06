@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeReflectionTypeMetadataTests {
    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func nominalToken(_ typeID: Int64) -> Int {
        Int(truncatingIfNeeded: (typeID << 9) | 6)
    }

    @Test func reflectedAnnotationClassUsesDeclaredIdentity() throws {
        let fqName = "sample.KUU1317Marker"
        let token = nominalToken(runtimeStableNominalTypeID(fqName: fqName))
        _ = __kk_kclass_register_metadata(
            token, makeRuntimeString(fqName), makeRuntimeString("KUU1317Marker"),
            0, 1 << 6, 0, 0, 0
        )
        let expected = __kk_kclass_create(token, 0)
        for cachedClass in [0, expected] {
            let value = registerRuntimeObject(RuntimeAnnotationBox(
                annotationFQName: fqName, arguments: [], annotationClassRaw: cachedClass
            ))
            let klass = __kk_kclass_of(value, Int(RuntimeTypeTokenEncoding.anyBase), makeRuntimeString("Any"))
            #expect(klass == expected)
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(klass)) == "KUU1317Marker")
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(klass)) == fqName)
        }
    }

    @Test func boundClassReferencesUseThrowableIdentityInsteadOfCatchType() throws {
        let exceptions: [(RuntimeThrowableBox, String)] = [
            (RuntimeIllegalArgumentExceptionBox(message: "argument"), "java.lang.IllegalArgumentException"),
            (RuntimeIllegalStateExceptionBox(message: "state"), "java.lang.IllegalStateException"),
        ]
        let fallback = nominalToken(runtimeStableNominalTypeID(fqName: "kotlin.Exception"))
        for (exception, displayName) in exceptions {
            let value = registerRuntimeObject(exception)
            let klass = __kk_kclass_of(value, fallback, makeRuntimeString("Exception"))
            let expectedToken = nominalToken(runtimeStableNominalTypeID(fqName: exception.exceptionFQName))
            #expect(try #require(runtimeKClassBox(from: klass)).typeToken == expectedToken)
            #expect(klass == __kk_kclass_create(expectedToken, 0))
            #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(klass)) == displayName.split(separator: ".").last.map(String.init))
            #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(klass)) == displayName)
        }
    }

    @Test func boundClassReferencesUseBoxedPrimitiveIdentity() throws {
        let values: [(Int, Int64)] = [
            (kk_box_int(1), RuntimeTypeTokenEncoding.intBase),
            (kk_box_byte(1), RuntimeTypeTokenEncoding.byteBase),
            (kk_box_short(1), RuntimeTypeTokenEncoding.shortBase),
            (kk_box_uint(1), RuntimeTypeTokenEncoding.uintBase),
            (kk_box_ubyte(1), RuntimeTypeTokenEncoding.ubyteBase),
            (kk_box_ushort(1), RuntimeTypeTokenEncoding.ushortBase),
            (kk_box_long(1), RuntimeTypeTokenEncoding.longBase),
            (kk_box_ulong(1), RuntimeTypeTokenEncoding.ulongBase),
            (kk_box_double(1), RuntimeTypeTokenEncoding.doubleBase),
            (kk_box_float(1), RuntimeTypeTokenEncoding.floatBase),
            (kk_box_bool(1), RuntimeTypeTokenEncoding.booleanBase),
            (kk_box_char(65), RuntimeTypeTokenEncoding.charBase),
            (makeRuntimeString("x"), RuntimeTypeTokenEncoding.stringBase),
            (kk_box_unit(0), RuntimeTypeTokenEncoding.unitBase),
        ]
        for (value, base) in values {
            let klass = __kk_kclass_of(value, Int(RuntimeTypeTokenEncoding.anyBase), 0)
            #expect(try #require(runtimeKClassBox(from: klass)).typeToken == Int(base))
            #expect(klass == __kk_kclass_create(Int(base), 0))
        }
    }

    @Test func boundClassReferencesUseNominalMetadataInsteadOfStaticHint() throws {
        let typeID: Int64 = 73001
        let token = nominalToken(typeID)
        _ = __kk_kclass_register_metadata(
            token, makeRuntimeString("sample.Derived"), makeRuntimeString("Derived"),
            0, 0, 0, 0, 0
        )
        let value = kk_object_new(0, Int(typeID))
        let klass = __kk_kclass_of(value, Int(RuntimeTypeTokenEncoding.anyBase), makeRuntimeString("Any"))
        #expect(try #require(runtimeKClassBox(from: klass)).typeToken == token)
        #expect(runtimeRenderAnyForPrint(__kk_kclass_simple_name(klass)) == "Derived")
        #expect(runtimeRenderAnyForPrint(__kk_kclass_qualified_name(klass)) == "sample.Derived")
    }

    @Test func kclassToStringUsesQualifiedNamesAcrossRenderers() {
        let cases: [(Int, String)] = [
            (Int(RuntimeTypeTokenEncoding.stringBase), "kotlin.String"),
            (Int(RuntimeTypeTokenEncoding.intBase), "kotlin.Int"),
        ]
        for (token, name) in cases {
            let klass = __kk_kclass_create(token, makeRuntimeString("IgnoredHint"))
            let expected = "class \(name)"
            #expect(runtimeElementToString(klass) == expected)
            #expect(runtimeRenderAnyForPrint(klass) == expected)
            #expect(extractString(from: kk_any_to_string(klass, 0)) == expected)
        }

        let token = nominalToken(73002)
        let klass = __kk_kclass_create(token, makeRuntimeString("Sample"))
        _ = __kk_kclass_register_metadata(
            token, makeRuntimeString("sample.Sample"), makeRuntimeString("Sample"),
            0, 0, 0, 0, 0
        )
        #expect(runtimeElementToString(klass) == "class sample.Sample")
        #expect(runtimeRenderAnyForPrint(klass) == "class sample.Sample")
        #expect(extractString(from: kk_any_to_string(klass, 0)) == "class sample.Sample")
    }

    @Test func reflectionBoxesCarryNominalHierarchyAndSharedNameDispatch() {
        registerReflectionRuntimeTypeMetadata()

        let functionName = makeRuntimeString("run")
        let propertyName = makeRuntimeString("value")
        let constructorName = makeRuntimeString("<init>")
        let function = __kk_kfunction_create(
            functionName, 0, makeRuntimeString("kotlin.String"), 0, 0, 0
        )
        let property = kk_kproperty_stub_create(propertyName, makeRuntimeString("kotlin.Int"))
        let kclass = __kk_kclass_create(71001, makeRuntimeString("Sample"))
        let constructor = __kk_kconstructor_create(
            constructorName, 0, makeRuntimeString("Sample"), 0, 1, 0, kclass
        )

        #expect(runtimeObjectTypeID(rawValue: function) == kFunctionRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: property) == kPropertyRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: constructor) == kConstructorRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: kclass) == kClassRuntimeTypeID)

        #expect(kk_op_is(function, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(function, nominalToken(kFunctionRuntimeTypeID)) == 1)
        #expect(kk_op_is(property, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(property, nominalToken(kPropertyRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kCallableRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kFunctionRuntimeTypeID)) == 1)
        #expect(kk_op_is(constructor, nominalToken(kConstructorRuntimeTypeID)) == 1)
        #expect(kk_op_is(kclass, nominalToken(kClassifierRuntimeTypeID)) == 1)

        #expect(__kk_kcallable_get_name(function) == functionName)
        #expect(__kk_kcallable_get_name(property) == propertyName)
        #expect(__kk_kcallable_get_name(constructor) == constructorName)

        let functionReturnType = __kk_kcallable_get_return_type(function)
        let propertyReturnType = __kk_kcallable_get_return_type(property)
        let constructorReturnType = __kk_kcallable_get_return_type(constructor)
        #expect(runtimeObjectTypeID(rawValue: functionReturnType) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: propertyReturnType) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: constructorReturnType) == kTypeRuntimeTypeID)
        #expect(__kk_ktype_classifier(functionReturnType) != runtimeNullSentinelInt)
        #expect(runtimeRenderAnyForPrint(functionReturnType) == "kotlin.String")
        #expect(runtimeRenderAnyForPrint(propertyReturnType) == "kotlin.Int")
        #expect(runtimeRenderAnyForPrint(constructorReturnType) == "Sample")

        let taggedFunction = kk_callable_ref_tag_kfunction(
            function, functionName, makeRuntimeString("kotlin.String"), 0, 0
        )
        let taggedProperty = kk_callable_ref_tag_kproperty(
            property, propertyName, makeRuntimeString("kotlin.Int"), 0
        )
        #expect(runtimeObjectTypeID(rawValue: __kk_kcallable_get_return_type(taggedFunction)) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: __kk_kcallable_get_return_type(taggedProperty)) == kTypeRuntimeTypeID)
    }

    @Test func typeReflectionBoxesCarryTheirDeclaredNominalTypes() {
        registerReflectionRuntimeTypeMetadata()

        let ktype = kk_typeof(71002, makeRuntimeString("Sample"), 0, 0)
        let projection = __kk_ktypeprojection_create(ktype, 2)
        let parameter = __kk_kparameter_create(
            0, makeRuntimeString("value"), makeRuntimeString("kotlin.Int"), 0, 2
        )

        #expect(runtimeObjectTypeID(rawValue: ktype) == kTypeRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: projection) == kTypeProjectionRuntimeTypeID)
        #expect(runtimeObjectTypeID(rawValue: parameter) == kParameterRuntimeTypeID)
        #expect(kk_op_is(ktype, nominalToken(kClassifierRuntimeTypeID)) == 1)
        #expect(kk_op_is(ktype, nominalToken(kTypeRuntimeTypeID)) == 1)
    }
}
