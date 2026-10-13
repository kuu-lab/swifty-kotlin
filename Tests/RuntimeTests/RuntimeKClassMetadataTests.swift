@testable import Runtime
import Testing

/// Tests for REFL-004: KClass binary metadata registry and accessors.
@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeKClassMetadataTests {

    // MARK: - RuntimeKClassMetadataEntry

    @Test func metadataEntryStoresAllFields() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "com.example.Foo",
            simpleName: "Foo",
            supertypeDisplayNames: ["com.example.Base"],
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 3,
            memberCount: 7,
            constructorCount: 0,
            isFinal: false,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        #expect(entry.qualifiedName == "com.example.Foo")
        #expect(entry.simpleName == "Foo")
        #expect(entry.supertypeDisplayNames == ["com.example.Base"])
        #expect(entry.isDataClass)
        #expect(!entry.isSealedClass)
        #expect(entry.fieldCount == 3)
        #expect(entry.memberCount == 7)
    }

    // MARK: - RuntimeKClassMetadataRegistry

    @Test func registryLookupReturnsNilForUnregisteredToken() {
        let result = runtimeKClassMetadataRegistry.lookup(typeToken: 999)
        #expect(result == nil)
    }

    @Test func registryRegisterAndLookup() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "test.MyClass",
            simpleName: "MyClass",
            supertypeDisplayNames: [],
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 2,
            memberCount: 5,
            constructorCount: 0,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 42, entry: entry)
        let result = runtimeKClassMetadataRegistry.lookup(typeToken: 42)
        #expect(result != nil)
        #expect(result?.qualifiedName == "test.MyClass")
        #expect(result?.simpleName == "MyClass")
        #expect(result?.supertypeDisplayNames == [])
        #expect(result?.fieldCount == 2)
    }

    @Test func registryResetClearsEntries() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "test.Temp",
            simpleName: "Temp",
            supertypeDisplayNames: [],
            isDataClass: false,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 0,
            memberCount: 0,
            constructorCount: 0,
            isFinal: false,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 100, entry: entry)
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: 100) != nil)

        runtimeKClassMetadataRegistry.reset()
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: 100) == nil)
    }

    // MARK: - RuntimeKClassBox Metadata Property

    @Test func kClassBoxMetadataReturnsNilWithoutRegistration() {
        let box = RuntimeKClassBox(typeToken: 77, nameHint: 0)
        #expect(box.metadata == nil)
    }

    @Test func kClassBoxMetadataReturnsRegisteredEntry() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "pkg.Widget",
            simpleName: "Widget",
            supertypeDisplayNames: ["pkg.Base"],
            isDataClass: true,
            isSealedClass: false,
            isValueClass: false,
            isInterface: false,
            isObject: false,
            isEnumClass: false,
            isAnnotationClass: false,
            isAbstract: false,
            fieldCount: 4,
            memberCount: 6,
            constructorCount: 0,
            isFinal: true,
            isOpen: false,
            visibility: "PUBLIC",
            typeParameterCount: 0
        )
        runtimeKClassMetadataRegistry.register(typeToken: 77, entry: entry)
        let box = RuntimeKClassBox(typeToken: 77, nameHint: 0)
        #expect(box.metadata != nil)
        #expect(box.metadata?.qualifiedName == "pkg.Widget")
        #expect(box.metadata?.isDataClass ?? false)
    }

    // MARK: - __kk_kclass_register_metadata C API

    @Test func qualifiedHintPreservesPackageWithoutMetadata() {
        let token = Int((Int64(1303) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase)
        let klass = __kk_kclass_create(token, makeRuntimeString("kotlin.collections.List"))
        #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(klass)) == "kotlin.collections.List")
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(klass)) == "List")
    }

    @Test func platformExceptionMappingDoesNotAffectUserClasses() {
        for (index, name, expected) in [
            (0, "kotlin.RuntimeException", "java.lang.RuntimeException"),
            (1, "sample.RuntimeException", "sample.RuntimeException"),
        ] {
            let token = Int((Int64(1310 + index) << RuntimeTypeTokenEncoding.payloadShift)
                | RuntimeTypeTokenEncoding.nominalBase)
            let hint = makeRuntimeString(name)
            let klass = __kk_kclass_create(token, hint)
            #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(klass)) == expected)
            _ = __kk_kclass_register_metadata(
                token, hint, makeRuntimeString("RuntimeException"), 0, 0, 0, 0, 1
            )
            #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(klass)) == expected)
        }
    }

    @Test func qualifiedNameUsesMetadataInsteadOfSimpleNameHint() {
        let typeToken = Int((Int64(1234) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase)
        let simpleName = makeRuntimeString("MyAnno")
        let kclass = __kk_kclass_create(typeToken, simpleName)
        #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(kclass)) == "MyAnno")

        _ = __kk_kclass_register_metadata(
            typeToken, makeRuntimeString("annotations.MyAnno"), simpleName,
            0, 1 << 6, 0, 0, 1
        )

        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kclass)) == "MyAnno")
        #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(kclass)) == "annotations.MyAnno")
        #expect(runtimeStringFromRaw(__kk_type_token_qualified_name(typeToken, simpleName)) == "annotations.MyAnno")
    }

    @Test func registerMetadataViaCABI() {
        // Create runtime strings for names.
        let qualifiedName = makeRuntimeString("com.example.Animal")
        let simpleName = makeRuntimeString("Animal")
        let supertypeName = makeRuntimeString("com.example.LivingThing")

        // flags: dataClass=1 (bit 0), abstract=1 (bit 7)
        let flags = (1 << 0) | (1 << 7) // 0b10000001 = 129

        let result = __kk_kclass_register_metadata(
            42, // typeToken
            qualifiedName,
            simpleName,
            supertypeName,
            flags,
            5, // fieldCount
            12, // memberCount
            2 // constructorCount
        )
        #expect(result == 0)

        let entry = runtimeKClassMetadataRegistry.lookup(typeToken: 42)
        #expect(entry != nil)
        #expect(entry?.qualifiedName == "com.example.Animal")
        #expect(entry?.simpleName == "Animal")
        #expect(entry?.supertypeDisplayNames == ["com.example.LivingThing"])
        #expect(entry?.isDataClass ?? false)
        #expect(entry?.isAbstract ?? false)
        #expect(!(entry?.isSealedClass ?? true))
        #expect(entry?.fieldCount == 5)
        #expect(entry?.memberCount == 12)
        #expect(entry?.constructorCount == 2)
    }

    @Test func registerMetadataWithNullSupertype() {
        let qualifiedName = makeRuntimeString("Simple")
        let simpleName = makeRuntimeString("Simple")

        _ = __kk_kclass_register_metadata(
            99, qualifiedName, simpleName,
            0, // null supertype
            0, // no flags
            1, -1, 0 // fieldCount=1, memberCount unknown, constructorCount=0
        )

        let entry = runtimeKClassMetadataRegistry.lookup(typeToken: 99)
        #expect(entry != nil)
        #expect(entry?.supertypeDisplayNames == [])
        #expect(!(entry?.isDataClass ?? true))
    }

    // MARK: - KClass Accessor Functions

    @Test func kClassIsDataReturnsCorrectValue() {
        let typeToken = 200
        registerTestMetadata(typeToken: typeToken, flags: 1 << 0) // dataClass
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_data(kclass) == 1)
    }

    @Test func kClassIsDataReturnsFalseWhenNotData() {
        let typeToken = 201
        registerTestMetadata(typeToken: typeToken, flags: 0)
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_data(kclass) == 0)
    }

    @Test func kClassIsSealedReturnsCorrectValue() {
        let typeToken = 202
        registerTestMetadata(typeToken: typeToken, flags: 1 << 1) // sealedClass
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_sealed(kclass) == 1)
    }

    @Test func kClassIsValueReturnsCorrectValue() {
        let typeToken = 203
        registerTestMetadata(typeToken: typeToken, flags: 1 << 2) // valueClass
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_value(kclass) == 1)
    }

    @Test func kClassIsInterfaceReturnsCorrectValue() {
        let typeToken = 204
        registerTestMetadata(typeToken: typeToken, flags: 1 << 3) // interface
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_interface(kclass) == 1)
    }

    @Test func kClassIsObjectReturnsCorrectValue() {
        let typeToken = 205
        registerTestMetadata(typeToken: typeToken, flags: 1 << 4) // object
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_object(kclass) == 1)
    }

    @Test func kClassIsEnumReturnsCorrectValue() {
        let typeToken = 206
        registerTestMetadata(typeToken: typeToken, flags: 1 << 5) // enumClass
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_enum(kclass) == 1)
    }

    @Test func kClassIsAbstractReturnsCorrectValue() {
        let typeToken = 207
        registerTestMetadata(typeToken: typeToken, flags: 1 << 7) // abstract
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_is_abstract(kclass) == 1)
    }

    // MARK: - Accessor Returns 0/False Without Metadata

    @Test func accessorsReturnDefaultsWithoutMetadata() {
        let kclass = __kk_kclass_create(8888, 0)
        #expect(__kk_kclass_is_data(kclass) == 0)
        #expect(__kk_kclass_is_sealed(kclass) == 0)
        #expect(__kk_kclass_is_value(kclass) == 0)
        #expect(__kk_kclass_is_interface(kclass) == 0)
        #expect(__kk_kclass_is_object(kclass) == 0)
        #expect(__kk_kclass_is_enum(kclass) == 0)
        #expect(__kk_kclass_is_abstract(kclass) == 0)
    }

    // MARK: - Multiple Flags

    @Test func multipleFlagsCombined() {
        let typeToken = 300
        // sealed + abstract
        let flags = (1 << 1) | (1 << 7)
        registerTestMetadata(typeToken: typeToken, flags: flags)
        let kclass = __kk_kclass_create(typeToken, 0)

        #expect(__kk_kclass_is_data(kclass) == 0)
        #expect(__kk_kclass_is_sealed(kclass) == 1)
        #expect(__kk_kclass_is_value(kclass) == 0)
        #expect(__kk_kclass_is_abstract(kclass) == 1)
    }

    // MARK: - KUU-1357: Multi-supertype registration and supertypes list

    @Test func registerMetadataSplitsJoinedSupertypes() {
        let typeToken = 310
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("test.C"),
            makeRuntimeString("C"),
            makeRuntimeString("test.P|test.I1|test.I2"),
            0, 0, 0, 0
        )
        let entry = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
        #expect(entry?.supertypeDisplayNames == ["test.P", "test.I1", "test.I2"])
    }

    @Test func supertypesReturnsKTypePerJoinedDisplayName() {
        let typeToken = 311
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("test.C"),
            makeRuntimeString("C"),
            makeRuntimeString("test.P|test.I1"),
            0, 0, 0, 0
        )
        let kclass = __kk_kclass_create(typeToken, makeRuntimeString("test.C"))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 2)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil)) == "test.P")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 1, nil)) == "test.I1")
    }

    @Test func supertypesFallsBackToBuiltinTable() {
        let token = Int((Int64(312) << RuntimeTypeTokenEncoding.payloadShift)
            | RuntimeTypeTokenEncoding.nominalBase)
        let kclass = __kk_kclass_create(token, makeRuntimeString("kotlin.Int"))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 3)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil)) == "kotlin.Number")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 1, nil)) == "kotlin.Comparable<kotlin.Int>")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 2, nil)) == "java.io.Serializable")
    }

    @Test func supertypesRendersGenericSupertypeArguments() {
        let typeToken = 313
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("test.G"),
            makeRuntimeString("G"),
            makeRuntimeString("kotlin.Comparable<test.G>"),
            0, 0, 0, 0
        )
        let kclass = __kk_kclass_create(typeToken, makeRuntimeString("test.G"))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 1)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil)) == "kotlin.Comparable<test.G>")
    }

    // MARK: - KUU-1357: Companion object and nested class registries

    @Test func companionRegistryRoundTripsThroughCAPI() {
        let typeToken = 320
        let companionToken = 321
        _ = __kk_kclass_register_companion(
            typeToken, companionToken, makeRuntimeString("test.WithComp.Companion")
        )
        let kclass = __kk_kclass_create(typeToken, makeRuntimeString("test.WithComp"))
        let companion = __kk_kclass_companion_object(kclass)
        #expect(companion != runtimeNullSentinelInt)
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(companion)) == "Companion")
    }

    @Test func companionObjectReturnsNullWithoutRegistration() {
        let kclass = __kk_kclass_create(322, makeRuntimeString("test.C"))
        #expect(__kk_kclass_companion_object(kclass) == runtimeNullSentinelInt)
    }

    @Test func nestedClassRegistryFeedsKClassList() {
        let typeToken = 330
        _ = __kk_kclass_register_nested_class(
            typeToken, 331, makeRuntimeString("test.Outer.Nested")
        )
        _ = __kk_kclass_register_nested_class(
            typeToken, 332, makeRuntimeString("test.Outer.Inn")
        )
        let kclass = __kk_kclass_create(typeToken, makeRuntimeString("test.Outer"))
        let list = __kk_kclass_nested_classes(kclass)
        #expect(kk_list_size(list) == 2)
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kk_list_get(list, 0, nil))) == "Nested")
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kk_list_get(list, 1, nil))) == "Inn")
    }

    @Test func nestedClassesReturnsEmptyWithoutRegistration() {
        let kclass = __kk_kclass_create(333, makeRuntimeString("test.Empty"))
        #expect(kk_list_size(__kk_kclass_nested_classes(kclass)) == 0)
    }

    // MARK: - KUU-1357: Packed KFunction modifier flags

    @Test func kFunctionPackedFlagsSurfaceThroughAccessors() {
        let function = __kk_kfunction_create(
            makeRuntimeString("ix"),
            1,
            makeRuntimeString("kotlin.Int"),
            (1 << 1) | (1 << 3), // inline + infix
            0,
            0
        )
        #expect(__kk_kfunction_is_suspend(function) == 0)
        #expect(__kk_kfunction_is_inline(function) == 1)
        #expect(__kk_kfunction_is_operator(function) == 0)
        #expect(__kk_kfunction_is_infix(function) == 1)
        #expect(__kk_kfunction_is_external(function) == 0)
    }

    @Test func kFunctionSuspendBitSurvivesPackedLayout() {
        let function = __kk_kfunction_create(
            makeRuntimeString("susp"),
            0, 0,
            (1 << 0) | (1 << 2), // suspend + operator
            0, 0
        )
        #expect(__kk_kfunction_is_suspend(function) == 1)
        #expect(__kk_kfunction_is_operator(function) == 1)
        #expect(__kk_kfunction_is_inline(function) == 0)
    }

    @Test func callableRefTagCarriesPackedFlags() {
        let tagged = kk_callable_ref_tag_kfunction(
            0x345000,
            makeRuntimeString("op"),
            makeRuntimeString("kotlin.Int"),
            1,
            1 << 2 // operator
        )
        #expect(__kk_kfunction_is_operator(tagged) == 1)
        #expect(__kk_kfunction_is_suspend(tagged) == 0)
        #expect(__kk_kfunction_is_inline(tagged) == 0)
    }

    @Test func callableRefTagLegacySuspendFlagStillWorks() {
        let tagged = kk_callable_ref_tag_kfunction(
            0x346000,
            makeRuntimeString("susp"),
            makeRuntimeString("kotlin.Unit"),
            0,
            1 // legacy bare suspend flag == packed bit0
        )
        #expect(__kk_kfunction_is_suspend(tagged) == 1)
        #expect(__kk_kfunction_is_inline(tagged) == 0)
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }

    private func registerTestMetadata(typeToken: Int, flags: Int) {
        let qualifiedName = makeRuntimeString("TestClass")
        let simpleName = makeRuntimeString("TestClass")
        _ = __kk_kclass_register_metadata(
            typeToken, qualifiedName, simpleName,
            0, flags, 0, 0, 0
        )
    }
}
