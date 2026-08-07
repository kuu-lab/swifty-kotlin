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
            supertypeName: "com.example.Base",
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
        #expect(entry.supertypeName == "com.example.Base")
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
            supertypeName: nil,
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
        #expect(result?.supertypeName == nil)
        #expect(result?.fieldCount == 2)
    }

    @Test func registryResetClearsEntries() {
        let entry = RuntimeKClassMetadataEntry(
            qualifiedName: "test.Temp",
            simpleName: "Temp",
            supertypeName: nil,
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
            supertypeName: "pkg.Base",
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
        #expect(entry?.supertypeName == "com.example.LivingThing")
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
        #expect(entry?.supertypeName == nil)
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
