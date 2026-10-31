@testable import Runtime
import Testing

/// Tests for REFL-004: KClass binary metadata registry and accessors.
@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeKClassMetadataTests {

    @Test func nativeClassPredicateRejectsOtherObjects() {
        let klass = __kk_kclass_create(1973, makeRuntimeString("test.NativeClassPredicate"))
        let other = registerRuntimeObject(RuntimeListBox(elements: []))
        #expect(__kk_kclass_is_runtime(klass) == 1)
        #expect(__kk_kclass_is_runtime(other) == 0)
        #expect(__kk_kclass_is_runtime(runtimeNullSentinelInt) == 0)
        #expect(__kk_kclass_is_runtime(0) == 0)
    }

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

    @Test(arguments: ["Byte", "Short", "Int", "Long", "Float", "Double"])
    func numericSupertypesIncludeSerializable(name: String) {
        let qualifiedName = "kotlin.\(name)"
        let kclass = __kk_kclass_create(nominalTypeToken(for: qualifiedName), makeRuntimeString(qualifiedName))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 3)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil)) == "kotlin.Number")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 1, nil)) == "kotlin.Comparable<\(qualifiedName)>")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 2, nil)) == "java.io.Serializable")

        let number = __kk_ktype_classifier(kk_list_get(list, 0, nil))
        let numberSupertypes = __kk_kclass_supertypes(number)
        #expect(kk_list_size(numberSupertypes) == 2)
        #expect(runtimeRenderAnyForPrint(kk_list_get(numberSupertypes, 0, nil)) == "kotlin.Any")
        #expect(runtimeRenderAnyForPrint(kk_list_get(numberSupertypes, 1, nil)) == "java.io.Serializable")
        let serializable = __kk_ktype_classifier(kk_list_get(numberSupertypes, 1, nil))
        #expect(__kk_kclass_isInstance(serializable, kk_box_int(42)) == 1)
    }

    @Test(arguments: ["Char", "Boolean"])
    func nonNumericPrimitiveSupertypesIncludeSerializable(name: String) {
        let qualifiedName = "kotlin.\(name)"
        let kclass = __kk_kclass_create(nominalTypeToken(for: qualifiedName), makeRuntimeString(qualifiedName))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 3)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil)) == "kotlin.Comparable<\(qualifiedName)>")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 1, nil)) == "java.io.Serializable")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 2, nil)) == "kotlin.Any")
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

    // MARK: - KUU-3811: FunctionN supertype names resolve to the function classifier

    /// A `kotlin.FunctionN` supertype display name is the same classifier as
    /// `FunctionN::class`: the KType renders in function-type notation like
    /// kotlinc and its classifier answers the flat `kotlin.FunctionN` name —
    /// not the internal `kotlin.Function.FunctionN` spelling.
    @Test func functionInterfaceSupertypeRendersFunctionNotation() {
        let typeToken = 345
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("test.Adder"),
            makeRuntimeString("Adder"),
            makeRuntimeString("kotlin.Function2<kotlin.Int, kotlin.Int, kotlin.Int>|kotlin.Any"),
            0, 0, 0, 0
        )
        let kclass = __kk_kclass_create(typeToken, makeRuntimeString("test.Adder"))
        let list = __kk_kclass_supertypes(kclass)
        #expect(kk_list_size(list) == 2)
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 0, nil))
            == "(kotlin.Int, kotlin.Int) -> kotlin.Int")
        #expect(runtimeRenderAnyForPrint(kk_list_get(list, 1, nil)) == "kotlin.Any")

        let classifier = __kk_ktype_classifier(kk_list_get(list, 0, nil))
        #expect(classifier != runtimeNullSentinelInt)
        #expect(runtimeStringFromRaw(__kk_kclass_qualified_name(classifier)) == "kotlin.Function2")
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(classifier)) == "Function2")
    }

    /// `kotlin.Function` (arity-agnostic) and non-canonical spellings keep
    /// nominal tokens — only `kotlin.FunctionN` maps to the function base.
    @Test func functionNameTokenMappingIsStrict() {
        func payload(_ token: Int64) -> Int64 {
            (token >> RuntimeTypeTokenEncoding.payloadShift)
                & RuntimeTypeTokenEncoding.payloadMask
        }
        let fn0 = runtimeTypeToken(forQualifiedName: "kotlin.Function0")
        #expect(fn0 & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.functionBase)
        #expect(payload(fn0) == 0)
        let fn22 = runtimeTypeToken(forQualifiedName: "kotlin.Function22")
        #expect(fn22 & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.functionBase)
        #expect(payload(fn22) == 22)
        let susp1 = runtimeTypeToken(forQualifiedName: "kotlin.coroutines.SuspendFunction1")
        #expect(susp1 & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.functionBase)
        #expect(payload(susp1) == Int64(1 | 0x100))
        // Not canonical FunctionN spellings → nominal tokens.
        for name in ["kotlin.Function", "kotlin.Function03", "kotlin.FunctionN", "kotlin.Functional"] {
            let token = runtimeTypeToken(forQualifiedName: name)
            #expect(token & RuntimeTypeTokenEncoding.baseMask
                == RuntimeTypeTokenEncoding.nominalBase, "\(name) must stay nominal")
        }
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

    @Test func repeatedNestedClassRegistrationIsIdempotentPerOwner() {
        let outer = 335
        let otherOuter = 336
        _ = __kk_kclass_register_nested_class(outer, 337, makeRuntimeString("test.Outer.One"))
        _ = __kk_kclass_register_nested_class(outer, 337, makeRuntimeString("test.Outer.One"))
        _ = __kk_kclass_register_nested_class(outer, 338, makeRuntimeString("test.Outer.Two"))
        _ = __kk_kclass_register_nested_class(otherOuter, 337, makeRuntimeString("test.Other.One"))

        let outerClass = __kk_kclass_create(outer, makeRuntimeString("test.Outer"))
        let nested = __kk_kclass_nested_classes(outerClass)
        #expect(kk_list_size(nested) == 2)
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kk_list_get(nested, 0, nil))) == "One")
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kk_list_get(nested, 1, nil))) == "Two")
        let otherClass = __kk_kclass_create(otherOuter, makeRuntimeString("test.Other"))
        #expect(kk_list_size(__kk_kclass_nested_classes(otherClass)) == 1)
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

    // MARK: - KUU-3828: anonymous object literal names

    @Test func anonymousMetadataReportsNullSimpleNameAndQualifiedName() {
        let typeToken = 340
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("__ObjectLiteral_0_1_2"),
            makeRuntimeString("__ObjectLiteral_0_1_2"),
            0,
            (1 << 13) | (1 << 14), // local + anonymous
            0, 0, 0
        )
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(__kk_kclass_simple_name(kclass) == runtimeNullSentinelInt)
        #expect(__kk_kclass_qualified_name(kclass) == runtimeNullSentinelInt)
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.isAnonymous == true)
        // The synthetic name stays in metadata for class-cast and toString
        // rendering; only the public simpleName hides it.
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.simpleName == "__ObjectLiteral_0_1_2")
    }

    @Test func namedLocalClassKeepsSimpleNameWhenAnonymousBitUnset() {
        let typeToken = 341
        _ = __kk_kclass_register_metadata(
            typeToken,
            makeRuntimeString("__localdecl_0.Local"),
            makeRuntimeString("Local"),
            0,
            1 << 13, // local only
            0, 0, 0
        )
        let kclass = __kk_kclass_create(typeToken, 0)
        #expect(runtimeStringFromRaw(__kk_kclass_simple_name(kclass)) == "Local")
        #expect(__kk_kclass_qualified_name(kclass) == runtimeNullSentinelInt)
        #expect(runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.isAnonymous == false)
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
