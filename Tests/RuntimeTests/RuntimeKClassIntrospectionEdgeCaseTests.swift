@testable import Runtime
import XCTest

/// Edge-case tests for STDLIB-REFLECT-067 — KClass<T> properties and introspection
/// available on common / Kotlin/Native targets.
///
/// Coverage:
///   - isInstance(value): basic true/false, null value (always false), unregistered type
///   - ::class / X::class class-literal syntax (KIR emission via StandaloneClassReferenceTests
///     already covers most paths; here we verify the runtime box identity/equality)
///   - KClass equality + hash: same typeToken → same box (interned), different → different
///   - enum class via ::class flags
///   - interface class-literal
///   - generic class (type arguments erased — KClass<List<Int>> == KClass<List<String>>)
///   - Any::class, Unit::class, Nothing::class special handling
///   - cast / safeCast helpers (isInstance-based semantics)
///   - member / field / constructor counts from registered metadata
final class RuntimeKClassIntrospectionEdgeCaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeStr(_ s: String) -> Int {
        s.withCString { cStr in
            cStr.withMemoryRebound(to: UInt8.self, capacity: max(1, s.utf8.count)) { ptr in
                Int(bitPattern: kk_string_from_utf8(ptr, Int32(s.utf8.count)))
            }
        }
    }

    private func strValue(from raw: Int) -> String? {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
    }

    private func registerClass(
        typeToken: Int,
        qualifiedName: String,
        simpleName: String,
        flags: Int = 0,
        fieldCount: Int = 0,
        memberCount: Int = 0,
        constructorCount: Int = 0
    ) -> Int {
        let qRaw = makeStr(qualifiedName)
        let sRaw = makeStr(simpleName)
        _ = __kk_kclass_register_metadata(
            typeToken, qRaw, sRaw, 0, flags,
            fieldCount, memberCount, constructorCount
        )
        return __kk_kclass_create(typeToken, sRaw)
    }

    private func runtimeListElements(from raw: Int) -> [Int] {
        guard raw != 0, raw != runtimeNullSentinelInt,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw)
        else {
            return []
        }
        return (tryCast(ptr, to: RuntimeListBox.self)?.elements) ?? []
    }

    // MARK: - isInstance

    func testIsInstanceReturnsFalseForUnregisteredTypeToken() {
        // A completely unknown typeToken — isInstance must not crash and must return 0.
        let kclass = __kk_kclass_create(99999, 0)
        let someValue = makeStr("hello")
        let result = __kk_kclass_isInstance(kclass, someValue)
        XCTAssertEqual(result, 0, "isInstance with unknown type should return false")
    }

    func testIsInstanceNullValueAlwaysFalse() {
        // Passing null (0) as value should always return 0 regardless of type.
        // Token 0x4000 = 16384: base = 0 (unknown/nominal default) and not nullable.
        let kclass = registerClass(typeToken: 0x4000, qualifiedName: "test.T", simpleName: "T")
        let result = __kk_kclass_isInstance(kclass, 0)
        XCTAssertEqual(result, 0, "isInstance(null) must be false")
    }

    func testIsInstanceNullSentinelValueAlwaysFalse() {
        // Use a typeToken where bit 8 (nullableBit = 0x100) is not set, so the type is non-nullable.
        // 0x201 & 0x100 = 0, 0x201 & 0xFF = 1 (anyBase would match). Use a high token: 0x2000 & 0x100 = 0.
        // Token 0x2000 = 8192: base = 0, isNullableTarget = false → kk_op_is(nullSentinel, 8192) = 0.
        let nonNullableToken = 0x2000 // base=0 (unknown), not nullable bit set
        let kclass = registerClass(typeToken: nonNullableToken, qualifiedName: "test.R", simpleName: "R")
        let result = __kk_kclass_isInstance(kclass, runtimeNullSentinelInt)
        XCTAssertEqual(result, 0, "isInstance(runtimeNullSentinel) must be false for non-nullable type token")
    }

    func testIsInstanceInvalidHandleReturnsFalse() {
        // Completely invalid kclassRaw.
        let result = __kk_kclass_isInstance(runtimeNullSentinelInt, makeStr("anything"))
        XCTAssertEqual(result, 0, "isInstance with invalid KClass handle must return false")
    }

    // MARK: - KClass identity / equality (interning)

    func testSameTypeTokenReturnsSameHandle() {
        // __kk_kclass_create interns boxes per typeToken.
        let token = 4001
        let a = __kk_kclass_create(token, 0)
        let b = __kk_kclass_create(token, 0)
        XCTAssertEqual(a, b, "Same typeToken must produce the same interned KClass handle")
    }

    func testDifferentTypeTokensReturnDifferentHandles() {
        let a = __kk_kclass_create(4002, 0)
        let b = __kk_kclass_create(4003, 0)
        XCTAssertNotEqual(a, b, "Different typeTokens must produce different KClass handles")
    }

    func testSameHandleEquality() {
        let token = 4004
        let kclass = __kk_kclass_create(token, 0)
        XCTAssertEqual(kclass, kclass, "A KClass handle must equal itself")
    }

    // MARK: - Generic class type-argument erasure

    func testGenericClassSameErasureEqualHandles() {
        // KClass<List<Int>> and KClass<List<String>> share the same erased typeToken
        // because runtime tokens do not encode generic arguments.
        // We model this by registering with the same token.
        let erasedToken = 5001
        let listIntKClass = __kk_kclass_create(erasedToken, makeStr("List"))
        let listStringKClass = __kk_kclass_create(erasedToken, makeStr("List"))
        XCTAssertEqual(
            listIntKClass, listStringKClass,
            "KClass handles for same erased token must be identical regardless of type arguments"
        )
    }

    func testGenericClassDifferentTypesSeparateHandles() {
        // Map and List have different tokens.
        let listToken = 5002
        let mapToken = 5003
        let listKClass = __kk_kclass_create(listToken, makeStr("List"))
        let mapKClass = __kk_kclass_create(mapToken, makeStr("Map"))
        XCTAssertNotEqual(listKClass, mapKClass)
    }

    // MARK: - Enum class via ::class

    func testEnumClassFlagSetOnMetadata() {
        // bit 5 = enumClass
        let token = 6001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "com.example.Color",
            simpleName: "Color",
            flags: 1 << 5
        )
        XCTAssertEqual(__kk_kclass_is_enum(kclass), 1, "Enum class flag should be 1")
        XCTAssertEqual(__kk_kclass_is_data(kclass), 0, "Enum class must not be a data class")
        XCTAssertEqual(__kk_kclass_is_interface(kclass), 0, "Enum class must not be an interface")
    }

    // MARK: - Interface class-literal

    func testInterfaceClassLiteralFlags() {
        // bit 3 = interface
        let token = 7001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "com.example.Printable",
            simpleName: "Printable",
            flags: 1 << 3
        )
        XCTAssertEqual(__kk_kclass_is_interface(kclass), 1, "Interface flag should be 1")
        XCTAssertEqual(__kk_kclass_is_abstract(kclass), 0, "Interface should not additionally be abstract unless flagged")
        XCTAssertEqual(__kk_kclass_is_sealed(kclass), 0)
    }

    // MARK: - cast / safeCast semantics (isInstance-based)

    func testSafeCastSemanticNullValueAlwaysFails() {
        // safeCast<T>(null) → null (isInstance is false for null)
        let kclass = registerClass(typeToken: 8001, qualifiedName: "test.Safe", simpleName: "Safe")
        XCTAssertEqual(__kk_kclass_isInstance(kclass, 0), 0, "safeCast null → null (isInstance false)")
    }

    func testSafeCastSemanticInvalidTypeAlwaysFails() {
        // A non-registered opaque pointer treated as value
        let kclass = registerClass(typeToken: 8002, qualifiedName: "test.Cast", simpleName: "Cast")
        // A raw int that is not a registered runtime object
        let notAnObject = 0xDEAD_BEEF
        let result = __kk_kclass_isInstance(kclass, notAnObject)
        XCTAssertEqual(result, 0, "safeCast with non-registered value → false")
    }

    func testMetadataOnlyMemberPropertiesAreEmpty() {
        let token = 9002
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Point",
            simpleName: "Point",
            flags: 1 << 0,
            fieldCount: 2,
            memberCount: 4
        )
        let props = runtimeListElements(from: __kk_kclass_member_properties(kclass))
        XCTAssertTrue(props.isEmpty, "metadata fieldCount must not create property placeholders")
    }

    func testRegisteredMemberPropertiesReturnRealHandles() {
        let token = 9004
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.RealPoint",
            simpleName: "RealPoint",
            flags: 1 << 0,
            fieldCount: 2,
            memberCount: 4
        )
        let prop = kk_kproperty_stub_create(makeStr("x"), makeStr("kotlin.Int"))
        _ = __kk_kclass_register_member(kclass, prop)

        XCTAssertEqual(runtimeListElements(from: __kk_kclass_properties(kclass)), [prop])
        XCTAssertEqual(runtimeListElements(from: __kk_kclass_member_properties(kclass)), [prop])
        XCTAssertEqual(runtimeListElements(from: __kk_kclass_declared_member_properties(kclass)), [prop])
    }

    func testMetadataOnlyConstructorsAreEmpty() {
        let token = 9003
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Widget",
            simpleName: "Widget",
            fieldCount: 1,
            memberCount: 3,
            constructorCount: 1
        )
        let constructors = runtimeListElements(from: __kk_kclass_constructors(kclass))
        XCTAssertTrue(constructors.isEmpty, "metadata constructorCount must not create constructor placeholders")
    }

    func testRegisteredConstructorsReturnRealHandles() {
        let token = 9005
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.RealWidget",
            simpleName: "RealWidget",
            fieldCount: 1,
            memberCount: 3,
            constructorCount: 1
        )
        let constructor = __kk_kconstructor_create(
            makeStr("<init>"),
            0,
            makeStr("test.RealWidget"),
            0,
            1,
            makeStr("PUBLIC"),
            kclass
        )

        XCTAssertEqual(runtimeListElements(from: __kk_kclass_constructors(kclass)), [constructor])
    }

    // MARK: - Multiple flags combined (abstract + sealed)

    func testAbstractSealedCombined() {
        let token = 10001
        let flags = (1 << 1) | (1 << 7) // sealed + abstract
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Base", simpleName: "Base", flags: flags)
        XCTAssertEqual(__kk_kclass_is_sealed(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_abstract(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_data(kclass), 0)
    }

    // MARK: - isFinal / isOpen (STDLIB-REFLECT-060 flags)

    func testIsFinalFlag() {
        let token = 10002
        let flags = 1 << 8 // isFinal
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Closed", simpleName: "Closed", flags: flags)
        XCTAssertEqual(__kk_kclass_is_final(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_open(kclass), 0)
    }

    func testIsOpenFlag() {
        let token = 10003
        let flags = 1 << 9 // isOpen
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Open", simpleName: "Open", flags: flags)
        XCTAssertEqual(__kk_kclass_is_open(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_final(kclass), 0)
    }

    // MARK: - Visibility

    func testVisibilityPublic() {
        let token = 10004
        _ = __kk_kclass_register_metadata_v2(
            token,
            makeStr("test.PubClass"),
            makeStr("PubClass"),
            0, 0, 0, 0, 0,
            makeStr("PUBLIC"),
            0
        )
        let kclass = __kk_kclass_create(token, 0)
        let vis = strValue(from: __kk_kclass_visibility(kclass))
        XCTAssertEqual(vis, "PUBLIC")
    }

    func testVisibilityInternal() {
        let token = 10005
        _ = __kk_kclass_register_metadata_v2(
            token,
            makeStr("test.InternalClass"),
            makeStr("InternalClass"),
            0, 0, 0, 0, 0,
            makeStr("INTERNAL"),
            0
        )
        let kclass = __kk_kclass_create(token, 0)
        let vis = strValue(from: __kk_kclass_visibility(kclass))
        XCTAssertEqual(vis, "INTERNAL")
    }

    // MARK: - Type parameters

    func testTypeParametersCountReturnsCorrectList() {
        let token = 12001
        _ = __kk_kclass_register_metadata_v2(
            token,
            makeStr("test.Container"),
            makeStr("Container"),
            0, 0, 0, 0, 0,
            makeStr("PUBLIC"),
            2 // 2 type parameters
        )
        let kclass = __kk_kclass_create(token, 0)
        let tpList = runtimeListElements(from: __kk_kclass_type_parameters(kclass))
        XCTAssertEqual(tpList.count, 2, "Generic class with 2 type params should expose 2 entries")
    }

    func testTypeParametersEmptyForNonGenericClass() {
        let token = 12002
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Simple", simpleName: "Simple")
        let tpList = runtimeListElements(from: __kk_kclass_type_parameters(kclass))
        XCTAssertEqual(tpList.count, 0)
    }

    // MARK: - __kk_kclass_get_arity (STDLIB-REFLECT-067)

    func testArityFromMetadata() {
        let token = 12003
        _ = __kk_kclass_register_metadata_v2(
            token,
            makeStr("test.Triple"),
            makeStr("Triple"),
            0, 0, 0, 0, 0,
            makeStr("PUBLIC"),
            3
        )
        let kclass = __kk_kclass_create(token, 0)
        XCTAssertEqual(__kk_kclass_get_arity(kclass), 3, "arity should equal the registered typeParameterCount")
    }

    func testArityZeroForNonGenericClass() {
        let token = 12004
        let kclass = registerClass(typeToken: token, qualifiedName: "test.Mono", simpleName: "Mono")
        XCTAssertEqual(__kk_kclass_get_arity(kclass), 0)
    }

    func testArityZeroForUnregisteredKClass() {
        let kclass = __kk_kclass_create(12005, 0)
        XCTAssertEqual(__kk_kclass_get_arity(kclass), 0, "unregistered KClass must return 0 for arity")
    }

    // MARK: - Declared member functions

    func testMetadataOnlyDeclaredMemberFunctionsAreEmpty() {
        let token = 13001
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.Service",
            simpleName: "Service",
            fieldCount: 1,
            memberCount: 5
        )
        let fns = runtimeListElements(from: __kk_kclass_declared_member_functions(kclass))
        XCTAssertTrue(fns.isEmpty, "metadata memberCount must not create function placeholders")
    }

    func testRegisteredDeclaredMemberFunctionsReturnRealHandles() {
        let token = 13002
        let kclass = registerClass(
            typeToken: token,
            qualifiedName: "test.RealService",
            simpleName: "RealService",
            fieldCount: 1,
            memberCount: 5
        )
        let fn = __kk_kfunction_create(makeStr("run"), 0, makeStr("kotlin.Unit"), 0, 0, 0)
        _ = __kk_kclass_register_member(kclass, fn)

        XCTAssertEqual(runtimeListElements(from: __kk_kclass_functions(kclass)), [fn])
        XCTAssertEqual(runtimeListElements(from: __kk_kclass_member_functions(kclass)), [fn])
        XCTAssertEqual(runtimeListElements(from: __kk_kclass_declared_member_functions(kclass)), [fn])
    }

    // MARK: - STDLIB-REFLECT-067: isInner / isCompanion / isFun type-kind flags

    func testIsInnerFlagSetWhenBitSet() {
        // bit 10 = inner
        let flags = 1 << 10
        let kclass = registerClass(typeToken: 14001, qualifiedName: "outer.Inner", simpleName: "Inner", flags: flags)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 0)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 0)
    }

    func testIsCompanionFlagSetWhenBitSet() {
        // bit 11 = companion
        let flags = 1 << 11
        let kclass = registerClass(typeToken: 14002, qualifiedName: "outer.Companion", simpleName: "Companion", flags: flags)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 0)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 0)
    }

    func testIsFunFlagSetWhenBitSet() {
        // bit 12 = funInterface
        let flags = 1 << 12
        let kclass = registerClass(typeToken: 14003, qualifiedName: "pkg.Transformer", simpleName: "Transformer", flags: flags)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 0)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 0)
    }

    func testTypeKindFlagsReturnZeroForUnregisteredKClass() {
        let kclass = __kk_kclass_create(14004, 0)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 0)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 0)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 0)
    }

    func testIsDataViaKClassAPIBitZero() {
        let flags = 1 << 0 // dataClass
        let kclass = registerClass(typeToken: 14005, qualifiedName: "pkg.Data", simpleName: "Data", flags: flags)
        XCTAssertEqual(__kk_kclass_is_data(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 0)
    }

    func testIsSealedViaKClassAPIBitOne() {
        let flags = 1 << 1 // sealedClass
        let kclass = registerClass(typeToken: 14006, qualifiedName: "pkg.Sealed", simpleName: "Sealed", flags: flags)
        XCTAssertEqual(__kk_kclass_is_sealed(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 0)
    }

    func testIsValueViaKClassAPIBitTwo() {
        let flags = 1 << 2 // valueClass
        let kclass = registerClass(typeToken: 14007, qualifiedName: "pkg.Value", simpleName: "Value", flags: flags)
        XCTAssertEqual(__kk_kclass_is_value(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 0)
    }

    func testMultipleTypeKindFlagsCanCoexist() {
        // inner (bit 10) + funInterface (bit 12)
        let flags = (1 << 10) | (1 << 12)
        let kclass = registerClass(typeToken: 14008, qualifiedName: "pkg.FunInner", simpleName: "FunInner", flags: flags)
        XCTAssertEqual(__kk_kclass_is_inner(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_fun(kclass), 1)
        XCTAssertEqual(__kk_kclass_is_companion(kclass), 0)
    }
}
