@testable import Runtime
import Foundation
import Testing

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

@Suite(.serialized, .runtimeIsolation(.gcAndMetadata))
struct RuntimeKTypeReflectionTests {

    private func makeRuntimeString(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(value.utf8.count)))
            }
        }
    }

    private func kk_println_any(_ value: Int) {
        __kk_print_raw(makeRuntimeString(runtimeRenderAnyForPrint(value) + "\n"))
    }

    private func kk_println_any(_ value: UnsafeMutableRawPointer?) {
        kk_println_any(Int(bitPattern: value))
    }

    private func registerKClassMetadata(typeToken: Int, qualifiedName: String, simpleName: String) {
        let qualifiedNameRaw = makeRuntimeString(qualifiedName)
        let simpleNameRaw = makeRuntimeString(simpleName)
        let result = __kk_kclass_register_metadata(typeToken, qualifiedNameRaw, simpleNameRaw, 0, 0, -1, -1, 0)
        #expect(result == 0)
    }

    private func makeKClassHandle(name: String, typeToken: Int) -> Int {
        let simpleName = name.split(separator: ".").last.map(String.init) ?? name
        registerKClassMetadata(typeToken: typeToken, qualifiedName: name, simpleName: simpleName)
        return __kk_kclass_create(typeToken, 0)
    }

    private func makeKTypeProjectionHandle(type: Int, variance: Int = 2) -> Int {
        __kk_ktypeprojection_create(type, variance)
    }

    private func makeKTypeHandle(
        name: String,
        typeToken: Int,
        arguments: [Int] = [],
        isNullable: Bool = false
    ) -> Int {
        _ = makeKClassHandle(name: name, typeToken: typeToken)
        let argsRaw: Int
        if arguments.isEmpty {
            argsRaw = 0
        } else {
            let array = kk_array_new(arguments.count)
            var thrown = 0
            for (index, argument) in arguments.enumerated() {
                _ = kk_array_set(array, index, argument, &thrown)
                #expect(thrown == 0)
            }
            argsRaw = kk_list_of(array, arguments.count)
        }
        return kk_typeof(typeToken, 0, argsRaw, isNullable ? 1 : 0)
    }

    @Test func ktypeAccessorsRoundTripBasicTypes() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 2)
        let nullableIntType = makeKTypeHandle(name: "kotlin.Int", typeToken: 3, isNullable: true)

        #expect(__kk_ktype_isMarkedNullable(stringType) == 0)
        #expect(__kk_ktype_isMarkedNullable(nullableIntType) == 1)

        let stringClassifier = __kk_ktype_classifier(stringType)
        #expect(stringClassifier != runtimeNullSentinelInt)
        #expect(runtimeListBox(from: __kk_ktype_arguments(stringType))?.elements.count == 0)
    }

    @Test func ktypeEqualityAndHashCodeAreStructural() {
        let firstLong = makeKTypeHandle(name: "kotlin.Long", typeToken: 102)
        let secondLong = makeKTypeHandle(name: "kotlin.Long", typeToken: 102)
        let firstList = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 103,
            arguments: [__kk_ktypeprojection_create(firstLong, 2)]
        )
        let secondList = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 103,
            arguments: [__kk_ktypeprojection_create(secondLong, 2)]
        )
        let nullableLong = makeKTypeHandle(name: "kotlin.Long", typeToken: 102, isNullable: true)

        #expect(firstLong != secondLong)
        #expect(kk_structural_eq(firstLong, secondLong) == 1)
        #expect(kk_any_hashCode(firstLong, 0) == kk_any_hashCode(secondLong, 0))
        #expect(kk_structural_eq(firstList, secondList) == 1)
        #expect(kk_any_hashCode(firstList, 0) == kk_any_hashCode(secondList, 0))
        #expect(kk_structural_eq(firstLong, nullableLong) == 0)
        #expect(kk_any_hashCode(firstLong, 0) != firstLong)
    }

    @Test func ktypeToStringRendersGenericArgumentsAndNullability() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 10)
        let nullableStringType = makeKTypeHandle(name: "kotlin.String", typeToken: 11, isNullable: true)
        let listType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 12,
            arguments: [makeKTypeProjectionHandle(type: stringType)]
        )
        let arrayType = makeKTypeHandle(
            name: "kotlin.Array",
            typeToken: 13,
            arguments: [makeKTypeProjectionHandle(type: stringType)]
        )
        let nestedType = makeKTypeHandle(
            name: "kotlin.collections.Map",
            typeToken: 14,
            arguments: [
                makeKTypeProjectionHandle(type: stringType),
                makeKTypeProjectionHandle(
                    type: makeKTypeHandle(
                        name: "kotlin.collections.List",
                        typeToken: 15,
                        arguments: [makeKTypeProjectionHandle(type: nullableStringType)]
                    )
                ),
            ]
        )

        #expect(runtimeRenderAnyForPrint(stringType) == "kotlin.String")
        #expect(runtimeRenderAnyForPrint(nullableStringType) == "kotlin.String?")
        #expect(runtimeRenderAnyForPrint(listType) == "kotlin.collections.List<kotlin.String>")
        #expect(runtimeRenderAnyForPrint(arrayType) == "kotlin.Array<kotlin.String>")
        #expect(
            runtimeRenderAnyForPrint(nestedType)
                == "kotlin.collections.Map<kotlin.String, kotlin.collections.List<kotlin.String?>>"
        )
    }

    @Test func ktypeArgumentsExposeKTypeProjectionsAndStar() {
        let elementType = makeKTypeHandle(name: "kotlin.Int", typeToken: 20)
        let projection = __kk_ktypeprojection_create(elementType, 2)
        let starProjection = __kk_ktypeprojection_create(0, -1)
        let arrayType = makeKTypeHandle(name: "kotlin.Array", typeToken: 21, arguments: [projection])

        #expect(runtimeRenderAnyForPrint(projection) == "kotlin.Int")
        #expect(runtimeRenderAnyForPrint(starProjection) == "*")

        let argumentsRaw = __kk_ktype_arguments(arrayType)
        let arguments = runtimeListBox(from: argumentsRaw)
        #expect(arguments?.elements.count == 1)
        #expect(arguments?.elements.first == projection)
        #expect(runtimeRenderAnyForPrint(arrayType) == "kotlin.Array<kotlin.Int>")
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: argumentsRaw)) } == "[kotlin.Int]")
    }

    @Test func ktypeBoxesRegisterSourceBackedPropertyGetters() throws {
        let elementType = makeKTypeHandle(name: "kotlin.Int", typeToken: 30)
        let projection = __kk_ktypeprojection_create(elementType, 2)
        let listType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 31,
            arguments: [projection]
        )
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KType"))
        let getterType = (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self

        let argumentsGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 0)
        let classifierGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 1)
        let nullableGetterRaw = kk_itable_lookup_dynamic(listType, interfaceTypeID, 2)
        #expect(argumentsGetterRaw != 0)
        #expect(classifierGetterRaw != 0)
        #expect(nullableGetterRaw != 0)

        let argumentsGetter = unsafeBitCast(argumentsGetterRaw, to: getterType)
        let classifierGetter = unsafeBitCast(classifierGetterRaw, to: getterType)
        let nullableGetter = unsafeBitCast(nullableGetterRaw, to: getterType)
        var thrown = 0
        let argumentsRaw = argumentsGetter(listType, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: argumentsRaw)?.elements == [projection])
        #expect(classifierGetter(listType, &thrown) == __kk_ktype_classifier(listType))
        #expect(nullableGetter(listType, &thrown) == 0)
        #expect(thrown == 0)
    }

    /// KUU-3895: unknown-token (base 0) KType boxes carry their own Kotlin
    /// type name — Kotlin `Nothing` renders `kotlin.Nothing` while its
    /// classifier hint is `java.lang.Void` (`Nothing::class` is `Void::class`)
    /// — and token-0 KClass boxes stay interned per name hint instead of
    /// collapsing into whichever registered first.
    @Test func unknownTokenKTypesKeepDistinctNameHints() {
        // The Nothing class metadata registers under token 0 (its real token);
        // token-0 KType boxes must not inherit its `java.lang.Void` rendering.
        registerKClassMetadata(
            typeToken: 0,
            qualifiedName: "java.lang.Void",
            simpleName: "Void"
        )

        let nothingType = kk_typeof(0, makeRuntimeString("java.lang.Void"), 0, 0)
        let nullableNothingType = kk_typeof(0, makeRuntimeString("kotlin.Nothing"), 0, 1)
        let otherUnknownType = kk_typeof(0, makeRuntimeString("com.example.Unresolved"), 0, 0)

        #expect(runtimeRenderAnyForPrint(nothingType) == "kotlin.Nothing")
        #expect(runtimeRenderAnyForPrint(nullableNothingType) == "kotlin.Nothing?")
        #expect(runtimeRenderAnyForPrint(otherUnknownType) == "com.example.Unresolved")

        let voidClass = __kk_kclass_create(0, makeRuntimeString("java.lang.Void"))
        let kotlinNothingClass = __kk_kclass_create(0, makeRuntimeString("kotlin.Nothing"))
        let unresolvedClass = __kk_kclass_create(0, makeRuntimeString("com.example.Unresolved"))
        #expect(voidClass != kotlinNothingClass)
        #expect(voidClass != unresolvedClass)
        #expect(kotlinNothingClass != unresolvedClass)
        #expect(__kk_kclass_create(0, makeRuntimeString("java.lang.Void")) == voidClass)
    }

    @Test func invalidHandlesReturnSentinels() {
        #expect(__kk_ktype_classifier(123_456) == runtimeNullSentinelInt)
        #expect(runtimeListBox(from: __kk_ktype_arguments(123_456))?.elements.count == 0)
        #expect(__kk_ktype_isMarkedNullable(123_456) == 0)
    }

    /// KUU-4022: the reified slot's copy helper must keep classifier and
    /// arguments while applying the use site's nullability, and each call
    /// must hand out a fresh box (KType `===` is observable).
    @Test func ktypeWithNullabilityCopiesStructureWithFreshIdentity() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: 40)
        let listType = makeKTypeHandle(
            name: "kotlin.collections.List",
            typeToken: 41,
            arguments: [__kk_ktypeprojection_create(stringType, 2)]
        )

        let copied = __kk_ktype_with_nullability(listType, 0)
        #expect(copied != listType)
        #expect(kk_structural_eq(copied, listType) == 1)
        #expect(kk_any_hashCode(copied, 0) == kk_any_hashCode(listType, 0))
        #expect(__kk_ktype_isMarkedNullable(copied) == 0)
        #expect(runtimeListBox(from: __kk_ktype_arguments(copied))?.elements.count == 1)

        let nullable = __kk_ktype_with_nullability(listType, 1)
        #expect(__kk_ktype_isMarkedNullable(nullable) == 1)
        #expect(kk_structural_eq(nullable, listType) == 0)

        let preserved = __kk_ktype_with_nullability(nullable, -1)
        #expect(__kk_ktype_isMarkedNullable(preserved) == 1)
        #expect(kk_structural_eq(preserved, nullable) == 1)
    }

    /// KUU-4022: a captured KType box derives the same interned
    /// `__kk_array_component_type` descriptor the compile-time descriptor
    /// path produced — nominal classifiers map to `(token, 0)` while
    /// `kotlin.Array` recurses into its element projection; `in`/`star`
    /// collapse to `Any`, and a `KTypeParameter` resolves to its bound.
    @Test func ktypeComponentDescriptorMatchesInternedDescriptors() {
        let stringType = makeKTypeHandle(name: "kotlin.String", typeToken: Int(RuntimeTypeTokenEncoding.stringBase))
        let arrayToken = Int(
            RuntimeTypeTokenEncoding.nominalBase
                | (Int64(runtimeStableNominalTypeID(fqName: "kotlin.Array"))
                    << RuntimeTypeTokenEncoding.payloadShift)
        )
        let arrayOfString = makeKTypeHandle(
            name: "kotlin.Array",
            typeToken: arrayToken,
            arguments: [__kk_ktypeprojection_create(stringType, 2)]
        )
        let arrayOfStar = makeKTypeHandle(
            name: "kotlin.Array",
            typeToken: arrayToken,
            arguments: [__kk_ktypeprojection_create(0, -1)]
        )

        let anyDescriptor = __kk_array_component_type(Int(RuntimeTypeTokenEncoding.anyBase), 0)
        let stringDescriptor = __kk_array_component_type(Int(RuntimeTypeTokenEncoding.stringBase), 0)

        #expect(__kk_ktype_component_descriptor(stringType) == stringDescriptor)
        #expect(
            __kk_ktype_component_descriptor(arrayOfString)
                == __kk_array_component_type(arrayToken, stringDescriptor)
        )
        #expect(
            __kk_ktype_component_descriptor(arrayOfStar)
                == __kk_array_component_type(arrayToken, anyDescriptor)
        )
        #expect(__kk_ktype_component_descriptor(123_456) == 0)
    }
}
