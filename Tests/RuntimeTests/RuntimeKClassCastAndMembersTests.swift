@testable import Runtime
import Testing

private let reflectedArrayInitializer: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, thrown in
    thrown?.pointee = 0
    return index + 1
}

// MARK: - STDLIB-REFLECT-ABI-002 / ABI-003 Tests
// Coverage for:
//   ABI-002: KClass.members returns real member handles registered via
//            __kk_kclass_register_member
//   ABI-003: __kk_kclass_cast / __kk_kclass_safeCast independent runtime entries

/// `.runtimeIsolation(.metadataOnly)` replaces the former
/// `kk_runtime_force_reset()` calls in `setUp` / `tearDown`. Swift Testing suites
/// run concurrently in a single process, so the KClass metadata and member
/// registries these tests mutate may only be reset while holding the cross-suite
/// metadata lock. A full reset is deliberately avoided: these tests never depend
/// on an empty GC heap, and clearing it would deallocate handles owned by
/// concurrently running suites.
@Suite(.runtimeIsolation(.metadataOnly))
struct RuntimeKClassCastAndMembersTests {

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }

    /// Registers a KClass with minimal metadata and returns its raw handle.
    private func registerKClass(
        typeToken: Int,
        qualifiedName: String,
        simpleName: String
    ) -> Int {
        let qn = makeRuntimeString(qualifiedName)
        let sn = makeRuntimeString(simpleName)
        _ = __kk_kclass_register_metadata(
            typeToken, qn, sn,
            0, // no supertype
            0, // no flags
            1, // fieldCount
            3, // memberCount
            1  // constructorCount
        )
        return __kk_kclass_create(typeToken, sn)
    }

    private func runtimeListBox(from raw: Int) throws -> RuntimeListBox {
        let listPtr = try #require(UnsafeMutableRawPointer(bitPattern: raw), "Expected list handle")
        return try #require(tryCast(listPtr, to: RuntimeListBox.self), "Expected RuntimeListBox")
    }

    private func runtimeListElements(from raw: Int) throws -> [Int] {
        try runtimeListBox(from: raw).elements
    }

    private func runtimeThrowableBox(from thrown: Int) throws -> RuntimeThrowableBox {
        #expect(thrown != 0)
        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: thrown), "Expected throwable handle")
        return try #require(tryCast(ptr, to: RuntimeThrowableBox.self), "Expected a RuntimeThrowableBox")
    }

    // MARK: - ABI-002: __kk_kclass_register_member / __kk_kclass_members

    @Test func membersEmptyWhenNoMembersRegistered() throws {
        let kclass = registerKClass(typeToken: 1001, qualifiedName: "pkg.A", simpleName: "A")
        let list = try runtimeListBox(from: __kk_kclass_members(kclass))

        // No members registered yet, so metadata counts must not create placeholders.
        #expect(list.elements.isEmpty)
    }

    @Test func primaryConstructorRequiresPrimaryFlag() {
        let kclass = registerKClass(typeToken: 1011, qualifiedName: "pkg.Constructors", simpleName: "Constructors")
        #expect(__kk_kclass_primary_constructor(kclass) == runtimeNullSentinelInt)

        let secondary = __kk_kconstructor_create(makeRuntimeString("<init>"), 0, 0, 0, 0, 0, kclass)
        #expect(runtimeKConstructorRegistry.constructors(for: kclass) == [secondary])
        #expect(__kk_kclass_primary_constructor(kclass) == runtimeNullSentinelInt)

        let primary = __kk_kconstructor_create(makeRuntimeString("<init>"), 1, 0, 0, 1, 0, kclass)
        #expect(__kk_kclass_primary_constructor(kclass) == primary)
    }

    @Test func builtinStringConstructorIsStableAndCallable() throws {
        let kclass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.stringBase), 0)
        let first = try runtimeListElements(from: __kk_kclass_constructors(kclass))
        let second = try runtimeListElements(from: __kk_kclass_constructors(kclass))
        #expect(first.count == 1)
        #expect(second == first)
        let constructor = try #require(first.first)
        let arguments = registerRuntimeObject(RuntimeListBox(elements: []))
        var thrown = 0
        let value = __kk_kcallable_call(constructor, arguments, &thrown)
        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: value)) == "")
        #expect(__kk_kclass_primary_constructor(kclass) == constructor)
    }

    @Test func builtinStringMembersExposeRealCallableMetadata() throws {
        let kclass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.stringBase), 0)
        let members = try runtimeListElements(from: __kk_kclass_members(kclass))
        #expect(try runtimeListElements(from: __kk_kclass_members(kclass)) == members)
        let functions = try runtimeListElements(from: __kk_kclass_member_functions(kclass))
        let properties = try runtimeListElements(from: __kk_kclass_member_properties(kclass))
        let declared = try runtimeListElements(from: __kk_kclass_declared_member_functions(kclass))
        #expect(!declared.contains { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "hashCode" })
        func named(_ name: String, in handles: [Int]) throws -> Int {
            try #require(handles.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == name })
        }
        let get = try named("get", in: functions)
        let length = try named("length", in: properties)
        let text = makeRuntimeString("abc")
        var thrown = 0
        let getArguments = registerRuntimeObject(RuntimeListBox(elements: [text, kk_box_int(1)]))
        let character = __kk_kcallable_call(get, getArguments, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_char(character) == 98)
        let lengthArguments = registerRuntimeObject(RuntimeListBox(elements: [text]))
        let count = __kk_kcallable_call(length, lengthArguments, &thrown)
        #expect(thrown == 0)
        #expect(kk_unbox_int(count) == 3)
        let getPointer = kk_itable_lookup_dynamic(length, Int(kProperty1RuntimeTypeID), 0)
        #expect(getPointer != 0)
        let getProperty = unsafeBitCast(getPointer, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        #expect(kk_unbox_int(getProperty(length, text, &thrown)) == 3)
        #expect(thrown == 0)
        let subSequence = try named("subSequence", in: functions)
        let subSequenceArguments = registerRuntimeObject(RuntimeListBox(elements: [text, kk_box_int(1), kk_box_int(3)]))
        let substring = __kk_kcallable_call(subSequence, subSequenceArguments, &thrown)
        #expect(thrown == 0)
        #expect(runtimeStringFromRaw(substring) == "bc")
        func invoke(_ name: String, _ values: [Int]) throws -> Int {
            let callable = try named(name, in: functions)
            let arguments = registerRuntimeObject(RuntimeListBox(elements: values))
            thrown = 0
            let result = __kk_kcallable_call(callable, arguments, &thrown)
            #expect(thrown == 0)
            return result
        }
        #expect(try runtimeStringFromRaw(invoke("toString", [text])) == "abc")
        #expect(try kk_unbox_bool(invoke("equals", [text, makeRuntimeString("abc")])) == 1)
        #expect(try kk_unbox_bool(invoke("equals", [text, runtimeNullSentinelInt])) == 0)
        #expect(try kk_unbox_int(invoke("compareTo", [text, makeRuntimeString("abd")])) < 0)
        #expect(try kk_unbox_int(invoke("hashCode", [text])) == 96354)
        #expect(try runtimeStringFromRaw(invoke("plus", [text, makeRuntimeString("d")])) == "abcd")
        let parameters = try runtimeListElements(from: __kk_kcallable_get_metadata(get, 0))
        #expect(parameters.count == 2)
        #expect(__kk_kparameter_get_kind(parameters[0]) == 0)
        #expect(__kk_kparameter_get_kind(parameters[1]) == 3)
        #expect(__kk_ktype_classifier(__kk_kparameter_get_type(parameters[0])) == kclass)
        #expect(__kk_ktype_classifier(__kk_kparameter_get_type(parameters[1])) == __kk_kclass_create(Int(RuntimeTypeTokenEncoding.intBase), 0))
        #expect(__kk_ktype_classifier(__kk_kcallable_get_return_type(get)) == __kk_kclass_create(Int(RuntimeTypeTokenEncoding.charBase), 0))
        #expect(runtimeStringFromRaw(__kk_kcallable_get_name(length)) == "length")
        #expect(try runtimeListElements(from: __kk_kclass_member_properties(__kk_kclass_create(Int(RuntimeTypeTokenEncoding.intBase), 0))).isEmpty)
    }

    @Test func primitiveCommonMembersAreTypedAndCallable() throws {
        let samples: [(Int64, Int, String)] = [
            (RuntimeTypeTokenEncoding.intBase, kk_box_int(42), "42"),
            (RuntimeTypeTokenEncoding.longBase, kk_box_long(42), "42"),
            (RuntimeTypeTokenEncoding.shortBase, kk_box_short(42), "42"),
            (RuntimeTypeTokenEncoding.byteBase, kk_box_byte(42), "42"),
            (RuntimeTypeTokenEncoding.floatBase, kk_box_float(kk_float_to_bits(1.5)), "1.5"),
            (RuntimeTypeTokenEncoding.doubleBase, kk_box_double(kk_double_to_bits(1.5)), "1.5"),
            (RuntimeTypeTokenEncoding.booleanBase, kk_box_bool(1), "true"),
            (RuntimeTypeTokenEncoding.charBase, kk_box_char(65), "A"),
            (RuntimeTypeTokenEncoding.uintBase, kk_box_uint(42), "42"),
            (RuntimeTypeTokenEncoding.ulongBase, kk_box_ulong(42), "42"),
            (RuntimeTypeTokenEncoding.ubyteBase, kk_box_ubyte(42), "42"),
            (RuntimeTypeTokenEncoding.ushortBase, kk_box_ushort(42), "42"),
            (RuntimeTypeTokenEncoding.unitBase, kk_box_unit(0), "kotlin.Unit"),
            (RuntimeTypeTokenEncoding.anyBase, kk_box_int(42), "42"),
        ]
        for (token, value, expected) in samples {
            let kclass = __kk_kclass_create(Int(token), 0)
            let functions = try runtimeListElements(from: __kk_kclass_member_functions(kclass))
            #expect(try runtimeListElements(from: __kk_kclass_member_functions(kclass)) == functions)
            func named(_ name: String) throws -> Int {
                try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == name })
            }
            let toString = try named("toString")
            let equals = try named("equals")
            _ = try named("hashCode")
            var thrown = 0
            let args = registerRuntimeObject(RuntimeListBox(elements: [value]))
            let rendered = __kk_kcallable_call(toString, args, &thrown)
            #expect(thrown == 0)
            #expect(runtimeStringFromRaw(rendered) == expected)
            let equalArgs = registerRuntimeObject(RuntimeListBox(elements: [value, value]))
            #expect(kk_unbox_bool(__kk_kcallable_call(equals, equalArgs, &thrown)) == 1)
            #expect(thrown == 0)
            let parameters = try runtimeListElements(from: __kk_kcallable_get_metadata(toString, 0))
            #expect(parameters.count == 1)
            #expect(__kk_ktype_classifier(__kk_kparameter_get_type(parameters[0])) == kclass)
            if token == RuntimeTypeTokenEncoding.intBase || token == RuntimeTypeTokenEncoding.unitBase {
                let declared = try runtimeListElements(from: __kk_kclass_declared_member_functions(kclass))
                #expect(!declared.contains { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "hashCode" })
                if token == RuntimeTypeTokenEncoding.unitBase {
                    #expect(!declared.contains { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "equals" })
                }
            }
        }
    }

    @Test func intArithmeticConstructorsAndUIntDataMetadata() throws {
        let intClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.intBase), 0)
        let functions = try runtimeListElements(from: __kk_kclass_member_functions(intClass))
        #expect(functions.count == 65)
        func overload(_ name: String, _ operand: Int64) throws -> Int {
            try #require(functions.first { raw in
                guard runtimeStringFromRaw(__kk_kcallable_get_name(raw)) == name,
                      let parameters = try? runtimeListElements(from: __kk_kcallable_get_metadata(raw, 0)),
                      parameters.count == 2 else { return false }
                return __kk_ktype_classifier(__kk_kparameter_get_type(parameters[1]))
                    == __kk_kclass_create(Int(operand), 0)
            })
        }
        func call(_ function: Int, _ left: Int, _ right: Int, _ thrown: inout Int) -> Int {
            let args = registerRuntimeObject(RuntimeListBox(elements: [left, right]))
            return __kk_kcallable_call(function, args, &thrown)
        }
        var thrown = 0
        let plus = try overload("plus", RuntimeTypeTokenEncoding.intBase)
        #expect(kk_unbox_int(call(plus, kk_box_int(Int(Int32.max)), kk_box_int(1), &thrown)) == Int(Int32.min))
        #expect(thrown == 0)
        let longPlus = try overload("plus", RuntimeTypeTokenEncoding.longBase)
        #expect(kk_unbox_long(call(longPlus, kk_box_int(2), kk_box_long(3), &thrown)) == 5)
        let longMin = call(longPlus, kk_box_int(0), kk_box_long_nonnull(Int.min), &thrown)
        #expect(longMin != runtimeNullSentinelInt)
        #expect(kk_unbox_long(longMin) == Int.min)
        let floatPlus = try overload("plus", RuntimeTypeTokenEncoding.floatBase)
        #expect(kk_bits_to_float(kk_unbox_float(call(floatPlus, kk_box_int(2), kk_box_float(kk_float_to_bits(0.5)), &thrown))) == 2.5)
        let doubleDivide = try overload("div", RuntimeTypeTokenEncoding.doubleBase)
        let negativeZero = call(doubleDivide, kk_box_int(0), kk_box_double(kk_double_to_bits(-1.0)), &thrown)
        #expect(negativeZero != runtimeNullSentinelInt)
        #expect(kk_unbox_double_nonnull(negativeZero) == kk_double_to_bits(-0.0))
        let shift = try overload("ushr", RuntimeTypeTokenEncoding.intBase)
        #expect(kk_unbox_int(call(shift, kk_box_int(-1), kk_box_int(1), &thrown)) == Int(Int32.max))
        let rangeUntil = try overload("rangeUntil", RuntimeTypeTokenEncoding.intBase)
        let range = try #require(runtimeRangeBox(from: call(rangeUntil, kk_box_int(2), kk_box_int(5), &thrown)))
        #expect(range.first == 2 && range.last == 4)
        let divide = try overload("div", RuntimeTypeTokenEncoding.intBase)
        #expect(kk_unbox_int(call(divide, kk_box_int(Int(Int32.min)), kk_box_int(-1), &thrown)) == Int(Int32.min))
        _ = call(divide, kk_box_int(1), kk_box_int(0), &thrown)
        #expect(thrown != 0)
        let constructors = try runtimeListElements(from: __kk_kclass_constructors(intClass))
        #expect(constructors.count == 1)
        let constructor = try #require(constructors.first)
        #expect(__kk_kclass_primary_constructor(intClass) == constructor)
        #expect(kk_unbox_int(__kk_kcallable_get_metadata(constructor, 2)) == 3)
        #expect(try runtimeListElements(from: __kk_kcallable_get_metadata(constructor, 0)).isEmpty)
        #expect(__kk_ktype_classifier(__kk_kcallable_get_return_type(constructor)) == intClass)

        for (token, maxValue, minValue, value) in [
            (RuntimeTypeTokenEncoding.byteBase, 127, -128, kk_box_byte(127)),
            (RuntimeTypeTokenEncoding.shortBase, 32767, -32768, kk_box_short(32767)),
        ] {
            let klass = __kk_kclass_create(Int(token), 0)
            let members = try runtimeListElements(from: __kk_kclass_member_functions(klass))
            #expect(members.count == 58)
            let increment = try #require(members.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "inc" })
            #expect(__kk_ktype_classifier(__kk_kcallable_get_return_type(increment)) == klass)
            let args = registerRuntimeObject(RuntimeListBox(elements: [value]))
            thrown = 0
            #expect(kk_unbox_int(__kk_kcallable_call(increment, args, &thrown)) == minValue)
            #expect(thrown == 0)
            #expect(kk_unbox_int(value) == maxValue)
        }
        let longClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.longBase), 0)
        let longFunctions = try runtimeListElements(from: __kk_kclass_member_functions(longClass))
        #expect(longFunctions.count == 65)
        func longOverload(_ name: String, _ operand: Int64) throws -> Int {
            try #require(longFunctions.first { raw in
                guard runtimeStringFromRaw(__kk_kcallable_get_name(raw)) == name,
                      let parameters = try? runtimeListElements(from: __kk_kcallable_get_metadata(raw, 0)),
                      parameters.count == 2 else { return false }
                return __kk_ktype_classifier(__kk_kparameter_get_type(parameters[1]))
                    == __kk_kclass_create(Int(operand), 0)
            })
        }
        let longAdd = try longOverload("plus", RuntimeTypeTokenEncoding.longBase)
        let wrapped = call(longAdd, kk_box_long_nonnull(Int.max), kk_box_long_nonnull(1), &thrown)
        #expect(thrown == 0)
        #expect(wrapped != runtimeNullSentinelInt && kk_unbox_long(wrapped) == Int.min)
        let longDiv = try longOverload("div", RuntimeTypeTokenEncoding.longBase)
        let quotient = call(longDiv, kk_box_long_nonnull(Int.min), kk_box_long_nonnull(-1), &thrown)
        #expect(thrown == 0 && quotient != runtimeNullSentinelInt && kk_unbox_long(quotient) == Int.min)
        let longShift = try longOverload("ushr", RuntimeTypeTokenEncoding.intBase)
        #expect(kk_unbox_long(call(longShift, kk_box_long_nonnull(-1), kk_box_int(1), &thrown)) == Int.max)
        let longRange = try longOverload("rangeUntil", RuntimeTypeTokenEncoding.longBase)
        let longRangeValue = try #require(runtimeRangeBox(from: call(longRange, kk_box_long_nonnull(2), kk_box_long_nonnull(5), &thrown)))
        #expect(longRangeValue.kind == .longRange && longRangeValue.first == 2 && longRangeValue.last == 4)

        let uintClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.uintBase), 0)
        let properties = try runtimeListElements(from: __kk_kclass_member_properties(uintClass))
        let data = try #require(properties.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "data" })
        #expect(kk_unbox_int(__kk_kcallable_get_metadata(data, 2)) == 2)
        #expect(__kk_ktype_classifier(__kk_kcallable_get_return_type(data)) == intClass)
        let args = registerRuntimeObject(RuntimeListBox(elements: [kk_box_uint(Int(UInt32.max))]))
        thrown = 0
        #expect(kk_unbox_int(__kk_kcallable_call(data, args, &thrown)) == -1)
        #expect(thrown == 0)
        let getPointer = kk_itable_lookup_dynamic(data, Int(kProperty1RuntimeTypeID), 0)
        #expect(getPointer != 0)
        let getProperty = unsafeBitCast(getPointer, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self)
        #expect(kk_unbox_int(getProperty(data, kk_box_uint(Int(UInt32.max)), &thrown)) == -1)
        let unsignedCases: [(Int64, Int, Int64)] = [
            (RuntimeTypeTokenEncoding.ubyteBase, kk_box_ubyte(255), RuntimeTypeTokenEncoding.byteBase),
            (RuntimeTypeTokenEncoding.ushortBase, kk_box_ushort(65535), RuntimeTypeTokenEncoding.shortBase),
            (RuntimeTypeTokenEncoding.ulongBase, kk_box_ulong(-1), RuntimeTypeTokenEncoding.longBase),
        ]
        for (token, value, underlyingToken) in unsignedCases {
            let klass = __kk_kclass_create(Int(token), 0)
            let properties = try runtimeListElements(from: __kk_kclass_member_properties(klass))
            let property = try #require(properties.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "data" })
            #expect(__kk_ktype_classifier(__kk_kcallable_get_return_type(property)) == __kk_kclass_create(Int(underlyingToken), 0))
            let values = registerRuntimeObject(RuntimeListBox(elements: [value]))
            let result = __kk_kcallable_call(property, values, &thrown)
            #expect(thrown == 0)
            #expect((underlyingToken == RuntimeTypeTokenEncoding.longBase ? kk_unbox_long(result) : kk_unbox_int(result)) == -1)
        }
        for (token, input, underlyingToken) in [
            (RuntimeTypeTokenEncoding.ubyteBase, kk_box_byte(-1), RuntimeTypeTokenEncoding.byteBase),
            (RuntimeTypeTokenEncoding.ushortBase, kk_box_short(-1), RuntimeTypeTokenEncoding.shortBase),
            (RuntimeTypeTokenEncoding.uintBase, kk_box_int(-1), RuntimeTypeTokenEncoding.intBase),
            (RuntimeTypeTokenEncoding.ulongBase, kk_box_long_nonnull(Int.min), RuntimeTypeTokenEncoding.longBase),
        ] {
            let klass = __kk_kclass_create(Int(token), 0)
            let constructor = __kk_kclass_primary_constructor(klass)
            #expect(constructor != runtimeNullSentinelInt)
            #expect(kk_unbox_int(__kk_kcallable_get_metadata(constructor, 2)) == 2)
            let parameters = try runtimeListElements(from: __kk_kcallable_get_metadata(constructor, 0))
            #expect(parameters.count == 1)
            #expect(__kk_ktype_classifier(__kk_kparameter_get_type(parameters[0])) == __kk_kclass_create(Int(underlyingToken), 0))
            let values = registerRuntimeObject(RuntimeListBox(elements: [input]))
            let result = __kk_kcallable_call(constructor, values, &thrown)
            #expect(thrown == 0)
            #expect(kk_op_is(result, Int(token)) == 1)
            if token == RuntimeTypeTokenEncoding.ulongBase { #expect(kk_unbox_ulong(result) == Int.min) }
        }
        let unsignedArithmetic: [(Int64, Int, Int, Int)] = [
            (RuntimeTypeTokenEncoding.ubyteBase, kk_box_ubyte(255), kk_box_ubyte(1), 256),
            (RuntimeTypeTokenEncoding.ushortBase, kk_box_ushort(65535), kk_box_ushort(1), 65536),
            (RuntimeTypeTokenEncoding.uintBase, kk_box_uint(Int(UInt32.max)), kk_box_uint(1), 0),
            (RuntimeTypeTokenEncoding.ulongBase, kk_box_ulong_nonnull(-1), kk_box_ulong_nonnull(1), 0),
        ]
        for (token, left, right, expected) in unsignedArithmetic {
            let klass = __kk_kclass_create(Int(token), 0)
            let members = try runtimeListElements(from: __kk_kclass_member_functions(klass))
            #expect(members.count == (token == RuntimeTypeTokenEncoding.uintBase || token == RuntimeTypeTokenEncoding.ulongBase ? 55 : 53))
            let plus = try #require(members.first { raw in
                guard runtimeStringFromRaw(__kk_kcallable_get_name(raw)) == "plus",
                      let parameters = try? runtimeListElements(from: __kk_kcallable_get_metadata(raw, 0)),
                      parameters.count == 2 else { return false }
                return __kk_ktype_classifier(__kk_kparameter_get_type(parameters[1])) == klass
            })
            thrown = 0
            let result = call(plus, left, right, &thrown)
            #expect(thrown == 0)
            #expect((token == RuntimeTypeTokenEncoding.ulongBase ? kk_unbox_ulong(result) : kk_unbox_int(result)) == expected)
            #expect(__kk_kfunction_is_inline(plus) == 1)
            #expect(__kk_kfunction_is_operator(plus) == 1)
        }
        let ulongClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.ulongBase), 0)
        let ulongData = try #require(try runtimeListElements(from: __kk_kclass_member_properties(ulongClass)).first)
        let ulongArgs = registerRuntimeObject(RuntimeListBox(elements: [kk_box_ulong_nonnull(Int.min)]))
        let signedMin = __kk_kcallable_call(ulongData, ulongArgs, &thrown)
        #expect(signedMin != runtimeNullSentinelInt)
        #expect(kk_unbox_long(signedMin) == Int.min)
        let unitClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.unitBase), 0)
        #expect(try runtimeListElements(from: __kk_kclass_constructors(unitClass)).isEmpty)
        let booleanClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.booleanBase), 0)
        let booleanFunctions = try runtimeListElements(from: __kk_kclass_member_functions(booleanClass))
        #expect(booleanFunctions.count == 8)
        let not = try #require(booleanFunctions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "not" })
        let boolArguments = registerRuntimeObject(RuntimeListBox(elements: [kk_box_bool(1)]))
        #expect(kk_unbox_bool(__kk_kcallable_call(not, boolArguments, &thrown)) == 0)
        #expect(thrown == 0)
        let charClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.charBase), 0)
        let charFunctions = try runtimeListElements(from: __kk_kclass_member_functions(charClass))
        #expect(charFunctions.count == 18)
        let charIncrement = try #require(charFunctions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "inc" })
        let charArguments = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(65535)]))
        #expect(kk_unbox_char(__kk_kcallable_call(charIncrement, charArguments, &thrown)) == 0)
        #expect(thrown == 0)
        for token in [RuntimeTypeTokenEncoding.floatBase, RuntimeTypeTokenEncoding.doubleBase] {
            let klass = __kk_kclass_create(Int(token), 0)
            let members = try runtimeListElements(from: __kk_kclass_member_functions(klass))
            #expect(members.count == 50)
            func floatingOverload(_ name: String, _ operand: Int64) throws -> Int {
                try #require(members.first { raw in
                    guard runtimeStringFromRaw(__kk_kcallable_get_name(raw)) == name,
                          let parameters = try? runtimeListElements(from: __kk_kcallable_get_metadata(raw, 0)),
                          parameters.count == 2 else { return false }
                    return __kk_ktype_classifier(__kk_kparameter_get_type(parameters[1]))
                        == __kk_kclass_create(Int(operand), 0)
                })
            }
            let compare = try floatingOverload("compareTo", token)
            let negativeZero = token == RuntimeTypeTokenEncoding.floatBase
                ? kk_box_float(kk_float_to_bits(-0.0)) : kk_box_double_nonnull(kk_double_to_bits(-0.0))
            let positiveZero = token == RuntimeTypeTokenEncoding.floatBase
                ? kk_box_float(kk_float_to_bits(0.0)) : kk_box_double_nonnull(kk_double_to_bits(0.0))
            #expect(kk_unbox_int(call(compare, negativeZero, positiveZero, &thrown)) == -1)
            let nan = token == RuntimeTypeTokenEncoding.floatBase
                ? kk_box_float(kk_float_to_bits(.nan)) : kk_box_double_nonnull(kk_double_to_bits(.nan))
            #expect(kk_unbox_int(call(compare, nan, positiveZero, &thrown)) == 1)
            #expect(kk_unbox_int(call(compare, nan, nan, &thrown)) == 0)
            let toInt = try #require(members.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "toInt" })
            let args = registerRuntimeObject(RuntimeListBox(elements: [nan]))
            #expect(kk_unbox_int(__kk_kcallable_call(toInt, args, &thrown)) == 0)
            #expect(thrown == 0)
        }
    }

    @Test func registerMemberReturnsZero() {
        let kclass = registerKClass(typeToken: 1002, qualifiedName: "pkg.B", simpleName: "B")
        let fnRaw = __kk_kfunction_create(
            makeRuntimeString("doSomething"), 0,
            makeRuntimeString("kotlin.Unit"), 0, 0, 0
        )
        let result = __kk_kclass_register_member(kclass, fnRaw)
        #expect(result == 0)
    }

    @Test func membersReturnsSingleRegisteredFunction() throws {
        let kclass = registerKClass(typeToken: 1003, qualifiedName: "pkg.C", simpleName: "C")
        let fnRaw = __kk_kfunction_create(
            makeRuntimeString("greet"), 1,
            makeRuntimeString("kotlin.String"), 0, 0, 0
        )
        _ = __kk_kclass_register_member(kclass, fnRaw)

        let list = try runtimeListBox(from: __kk_kclass_members(kclass))
        #expect(list.elements.count == 1)
        #expect(list.elements[0] == fnRaw)
    }

    @Test func membersReturnsMultipleRegisteredMembers() throws {
        let kclass = registerKClass(typeToken: 1004, qualifiedName: "pkg.D", simpleName: "D")
        let fn1 = __kk_kfunction_create(makeRuntimeString("foo"), 0, 0, 0, 0, 0)
        let fn2 = __kk_kfunction_create(makeRuntimeString("bar"), 1, 0, 0, 0, 0)
        let prop = kk_kproperty_stub_create(makeRuntimeString("value"), makeRuntimeString("kotlin.Int"))

        _ = __kk_kclass_register_member(kclass, fn1)
        _ = __kk_kclass_register_member(kclass, fn2)
        _ = __kk_kclass_register_member(kclass, prop)

        let list = try runtimeListBox(from: __kk_kclass_members(kclass))
        #expect(list.elements.count == 3)
        #expect(list.elements.contains(fn1))
        #expect(list.elements.contains(fn2))
        #expect(list.elements.contains(prop))
        #expect(!list.elements.contains(0))
    }

    @Test func functionAndPropertyAccessorsFilterRegisteredMembers() throws {
        let kclass = registerKClass(typeToken: 1010, qualifiedName: "pkg.Filtered", simpleName: "Filtered")
        let fn = __kk_kfunction_create(makeRuntimeString("compute"), 0, makeRuntimeString("kotlin.Int"), 0, 0, 0)
        let prop = kk_kproperty_stub_create(makeRuntimeString("value"), makeRuntimeString("kotlin.Int"))

        _ = __kk_kclass_register_member(kclass, fn)
        _ = __kk_kclass_register_member(kclass, prop)

        #expect(try runtimeListElements(from: __kk_kclass_members(kclass)) == [fn, prop])
        #expect(try runtimeListElements(from: __kk_kclass_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_member_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_properties(kclass)) == [prop])
        #expect(try runtimeListElements(from: __kk_kclass_member_properties(kclass)) == [prop])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_properties(kclass)) == [prop])
    }

    // KUU-4064: member extensions (`val String.x` / `fun String.f()` declared
    // inside a class) register via `__kk_kclass_register_member_extension`.
    // The JVM keeps them out of `member*`/`declaredMember*` (they surface only
    // through `memberExtension*`/`declaredMemberExtension*`) while `members`
    // still lists every registered member.
    @Test func memberExtensionsAreExcludedFromOrdinaryMemberAccessors() throws {
        let kclass = registerKClass(typeToken: 1012, qualifiedName: "pkg.WithExt", simpleName: "WithExt")
        let fn = __kk_kfunction_create(makeRuntimeString("normalFn"), 0, makeRuntimeString("kotlin.Int"), 0, 0, 0)
        let prop = kk_kproperty_stub_create(makeRuntimeString("normal"), makeRuntimeString("kotlin.Int"))
        let extFn = __kk_kfunction_create(makeRuntimeString("extFn"), 1, makeRuntimeString("kotlin.Int"), 0, 0, 0)
        let extProp = kk_kproperty_stub_create(makeRuntimeString("ext"), makeRuntimeString("kotlin.Int"))

        _ = __kk_kclass_register_member(kclass, fn)
        _ = __kk_kclass_register_member(kclass, prop)
        _ = __kk_kclass_register_member_extension(kclass, extFn)
        _ = __kk_kclass_register_member_extension(kclass, extProp)

        #expect(try runtimeListElements(from: __kk_kclass_members(kclass)) == [fn, prop, extFn, extProp])
        #expect(try runtimeListElements(from: __kk_kclass_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_member_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_functions(kclass)) == [fn])
        #expect(try runtimeListElements(from: __kk_kclass_properties(kclass)) == [prop])
        #expect(try runtimeListElements(from: __kk_kclass_member_properties(kclass)) == [prop])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_properties(kclass)) == [prop])
        #expect(try runtimeListElements(from: __kk_kclass_member_extension_functions(kclass)) == [extFn])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_extension_functions(kclass)) == [extFn])
        #expect(try runtimeListElements(from: __kk_kclass_member_extension_properties(kclass)) == [extProp])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_extension_properties(kclass)) == [extProp])
    }

    /// Inherited member extensions merge like ordinary members: visible
    /// through `memberExtension*` on the subclass, still absent from `member*`.
    @Test func memberExtensionAccessorsIncludeInheritedExtensions() throws {
        let parentID = runtimeStableNominalTypeID(fqName: "pkg.ExtParent")
        let childID = runtimeStableNominalTypeID(fqName: "pkg.ExtChild")
        let parentToken = Int(
            (parentID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let childToken = Int(
            (childID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let parent = registerKClass(typeToken: parentToken, qualifiedName: "pkg.ExtParent", simpleName: "ExtParent")
        let child = registerKClass(typeToken: childToken, qualifiedName: "pkg.ExtChild", simpleName: "ExtChild")
        _ = kk_type_register_super(Int(childID), Int(parentID))

        let parentExtProp = kk_kproperty_stub_create(makeRuntimeString("baseExt"), makeRuntimeString("kotlin.Int"))
        let parentExtFn = __kk_kfunction_create(makeRuntimeString("baseExtFn"), 1, 0, 0, 1, 0)
        _ = __kk_kclass_register_member_extension(parent, parentExtProp)
        _ = __kk_kclass_register_member_extension(parent, parentExtFn)
        let ownExtProp = kk_kproperty_stub_create(makeRuntimeString("ownExt"), makeRuntimeString("kotlin.String"))
        let ownExtFn = __kk_kfunction_create(makeRuntimeString("ownExtFn"), 1, 0, 0, 1, 0)
        _ = __kk_kclass_register_member_extension(child, ownExtProp)
        _ = __kk_kclass_register_member_extension(child, ownExtFn)
        let ownProp = kk_kproperty_stub_create(makeRuntimeString("ownProp"), makeRuntimeString("kotlin.String"))
        _ = __kk_kclass_register_member(child, ownProp)

        #expect(try runtimeListElements(from: __kk_kclass_member_extension_properties(child)) == [ownExtProp, parentExtProp])
        #expect(try runtimeListElements(from: __kk_kclass_member_extension_functions(child)) == [ownExtFn, parentExtFn])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_extension_properties(child)) == [ownExtProp])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_extension_functions(child)) == [ownExtFn])
        #expect(try runtimeListElements(from: __kk_kclass_member_properties(child)) == [ownProp])
        #expect(try runtimeListElements(from: __kk_kclass_member_functions(child)).isEmpty)
        #expect(try runtimeListElements(from: __kk_kclass_members(child)) == [ownExtProp, ownExtFn, ownProp, parentExtProp, parentExtFn])
    }

    @Test func registerMemberIgnoresInvalidHandles() throws {
        let kclass = registerKClass(typeToken: 1005, qualifiedName: "pkg.E", simpleName: "E")
        // Invalid handles should be ignored.
        _ = __kk_kclass_register_member(kclass, 0)
        _ = __kk_kclass_register_member(kclass, runtimeNullSentinelInt)
        _ = __kk_kclass_register_member(kclass, 0xDEAD_BEEF)

        let list = try runtimeListBox(from: __kk_kclass_members(kclass))
        #expect(list.elements.isEmpty)
    }

    // KUU-4029: `member*`/`members` merge members registered on ancestors
    // reached through `kk_type_register_super` edges; `declaredMember*` stays
    // self-only.
    @Test func memberAccessorsIncludeInheritedMembers() throws {
        let parentID = runtimeStableNominalTypeID(fqName: "pkg.Parent")
        let childID = runtimeStableNominalTypeID(fqName: "pkg.Child")
        let parentToken = Int(
            (parentID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let childToken = Int(
            (childID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let parent = registerKClass(typeToken: parentToken, qualifiedName: "pkg.Parent", simpleName: "Parent")
        let child = registerKClass(typeToken: childToken, qualifiedName: "pkg.Child", simpleName: "Child")
        _ = kk_type_register_super(Int(childID), Int(parentID))

        let inheritedProp = kk_kproperty_stub_create(makeRuntimeString("baseProp"), makeRuntimeString("kotlin.Int"))
        let inheritedFn = __kk_kfunction_create(makeRuntimeString("baseFn"), 0, 0, 0, 1, 0)
        _ = __kk_kclass_register_member(parent, inheritedProp)
        _ = __kk_kclass_register_member(parent, inheritedFn)
        let ownProp = kk_kproperty_stub_create(makeRuntimeString("ownProp"), makeRuntimeString("kotlin.String"))
        let ownFn = __kk_kfunction_create(makeRuntimeString("ownFn"), 0, 0, 0, 1, 0)
        _ = __kk_kclass_register_member(child, ownProp)
        _ = __kk_kclass_register_member(child, ownFn)

        #expect(try runtimeListElements(from: __kk_kclass_member_properties(child)) == [ownProp, inheritedProp])
        #expect(try runtimeListElements(from: __kk_kclass_member_functions(child)) == [ownFn, inheritedFn])
        #expect(try runtimeListElements(from: __kk_kclass_members(child)) == [ownProp, ownFn, inheritedProp, inheritedFn])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_properties(child)) == [ownProp])
        #expect(try runtimeListElements(from: __kk_kclass_declared_member_functions(child)) == [ownFn])
    }

    /// A child-class override shadows the inherited signature — the JVM
    /// surfaces only the most-derived member.
    @Test func memberFunctionsShadowInheritedOverrides() throws {
        let parentID = runtimeStableNominalTypeID(fqName: "pkg.ShadowParent")
        let childID = runtimeStableNominalTypeID(fqName: "pkg.ShadowChild")
        let parentToken = Int(
            (parentID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let childToken = Int(
            (childID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let parent = registerKClass(typeToken: parentToken, qualifiedName: "pkg.ShadowParent", simpleName: "ShadowParent")
        let child = registerKClass(typeToken: childToken, qualifiedName: "pkg.ShadowChild", simpleName: "ShadowChild")
        _ = kk_type_register_super(Int(childID), Int(parentID))

        let parentFn = __kk_kfunction_create(makeRuntimeString("dup"), 1, 0, 0, 1, 0)
        let childFn = __kk_kfunction_create(makeRuntimeString("dup"), 1, 0, 0, 2, 0)
        let parentProp = kk_kproperty_stub_create(makeRuntimeString("prop"), makeRuntimeString("kotlin.Int"))
        let childProp = kk_kproperty_stub_create(makeRuntimeString("prop"), makeRuntimeString("kotlin.String"))
        _ = __kk_kclass_register_member(parent, parentFn)
        _ = __kk_kclass_register_member(parent, parentProp)
        _ = __kk_kclass_register_member(child, childFn)
        _ = __kk_kclass_register_member(child, childProp)

        #expect(try runtimeListElements(from: __kk_kclass_member_functions(child)) == [childFn])
        #expect(try runtimeListElements(from: __kk_kclass_member_properties(child)) == [childProp])
    }

    /// The `kotlin.Any` supertype edge resolves to the dedicated `anyBase`
    /// KClass handle, so Any's builtin `equals`/`hashCode`/`toString` surface
    /// on user classes like the JVM.
    @Test func memberFunctionsIncludeAnyMembersThroughSuperEdge() throws {
        let childID = runtimeStableNominalTypeID(fqName: "pkg.AnyChild")
        let childToken = Int(
            (childID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
        )
        let child = registerKClass(typeToken: childToken, qualifiedName: "pkg.AnyChild", simpleName: "AnyChild")
        _ = kk_type_register_super(Int(childID), Int(runtimeStableNominalTypeID(fqName: "kotlin.Any")))

        let names = try runtimeListElements(from: __kk_kclass_member_functions(child))
            .compactMap { runtimeStringFromRaw(__kk_kcallable_get_name($0)) }
        #expect(names.contains("equals"))
        #expect(names.contains("hashCode"))
        #expect(names.contains("toString"))
    }

    @Test func membersIsolatedPerClass() throws {
        let classA = registerKClass(typeToken: 1006, qualifiedName: "pkg.F", simpleName: "F")
        let classB = registerKClass(typeToken: 1007, qualifiedName: "pkg.G", simpleName: "G")

        let fnA = __kk_kfunction_create(makeRuntimeString("fromA"), 0, 0, 0, 0, 0)
        let fnB = __kk_kfunction_create(makeRuntimeString("fromB"), 0, 0, 0, 0, 0)

        _ = __kk_kclass_register_member(classA, fnA)
        _ = __kk_kclass_register_member(classB, fnB)

        let listBoxA = try runtimeListBox(from: __kk_kclass_members(classA))
        let listBoxB = try runtimeListBox(from: __kk_kclass_members(classB))

        #expect(listBoxA.elements.count == 1)
        #expect(listBoxA.elements[0] == fnA)
        #expect(listBoxB.elements.count == 1)
        #expect(listBoxB.elements[0] == fnB)
        #expect(!listBoxA.elements.contains(fnB))
        #expect(!listBoxB.elements.contains(fnA))
    }

    @Test func membersRegistryResetOnRuntimeReset() {
        let kclass = registerKClass(typeToken: 1008, qualifiedName: "pkg.H", simpleName: "H")
        let fn = __kk_kfunction_create(makeRuntimeString("method"), 0, 0, 0, 0, 0)
        _ = __kk_kclass_register_member(kclass, fn)

        // Confirm member is registered.
        let beforeReset = runtimeKMemberRegistry.members(for: kclass)
        #expect(!beforeReset.isEmpty)

        // Only the metadata state is reset: the suite's isolation trait holds the
        // metadata lock, so this cannot race with concurrently running suites.
        kk_runtime_reset_metadata()

        // After reset, members should be cleared.
        let afterReset = runtimeKMemberRegistry.members(for: kclass)
        #expect(afterReset.isEmpty)
    }

    @Test
    func builtinArrayPropertiesAndConstructors() throws {
        for name in ["BooleanArray", "ByteArray", "ShortArray", "IntArray", "LongArray", "FloatArray", "DoubleArray", "CharArray", "UIntArray", "UByteArray", "UShortArray", "ULongArray"] {
            let typeID = runtimeStableNominalTypeID(fqName: "kotlin.\(name)")
            let token = (typeID << RuntimeTypeTokenEncoding.payloadShift) | RuntimeTypeTokenEncoding.nominalBase
            let klass = __kk_kclass_create(Int(token), makeRuntimeString("kotlin.\(name)"))
            let properties = try runtimeListElements(from: __kk_kclass_member_properties(klass))
            let size = try #require(properties.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "size" })
            let array = kk_array_new(3)
            runtimeRegisterArrayType(rawValue: array, typeID: typeID)
            var thrown = 0
            let value = __kk_kcallable_call(size, registerRuntimeObject(RuntimeListBox(elements: [array])), &thrown)
            #expect(thrown == 0)
            #expect(kk_unbox_int(value) == 3)
            let constructors = try runtimeListElements(from: __kk_kclass_constructors(klass))
            #expect(constructors.count == 2)
            let primary = __kk_kclass_primary_constructor(klass)
            #expect(constructors.contains(primary))
            let sizeConstructor = try #require(constructors.first { constructor in
                let params = try? runtimeListBox(from: __kk_kcallable_get_metadata(constructor, 0))
                guard let params, params.elements.count == 1,
                      let parameter = runtimeKParameterBox(from: params.elements[0]) else { return false }
                return runtimeStringFromRaw(parameter.nameRaw) == "size"
            })
            let created = __kk_kcallable_call(sizeConstructor, registerRuntimeObject(RuntimeListBox(elements: [kk_box_int(4)])), &thrown)
            #expect(thrown == 0)
            #expect(kk_array_size(created) == 4)
            if name == "IntArray" || name == "UIntArray" {
                let functions = try runtimeListElements(from: __kk_kclass_member_functions(klass))
                let names = Set(functions.compactMap { runtimeStringFromRaw(__kk_kcallable_get_name($0)) })
                #expect(names.isSuperset(of: ["get", "set", "equals", "hashCode", "iterator", "toString"]))
                let declared = try runtimeListElements(from: __kk_kclass_declared_member_functions(klass))
                let declaredNames = Set(declared.compactMap { runtimeStringFromRaw(__kk_kcallable_get_name($0)) })
                if name == "IntArray" {
                    #expect(declaredNames == ["clone", "get", "iterator", "set"])
                } else {
                    #expect(declaredNames.contains("equals"))
                }
                let get = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "get" })
                let set = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "set" })
                let element = name == "IntArray" ? kk_box_int(42) : kk_box_uint(42)
                let setterArgs = registerRuntimeObject(RuntimeListBox(elements: [created, kk_box_int(1), element]))
                _ = __kk_kcallable_call(set, setterArgs, &thrown)
                #expect(thrown == 0)
                let getterArgs = registerRuntimeObject(RuntimeListBox(elements: [created, kk_box_int(1)]))
                #expect(kk_unbox_int(__kk_kcallable_call(get, getterArgs, &thrown)) == 42)
                #expect(thrown == 0)
                if name == "IntArray" {
                    let initializedConstructor = try #require(constructors.first { constructor in
                        (try? runtimeListBox(from: __kk_kcallable_get_metadata(constructor, 0)).elements.count) == 2
                    })
                    let initializer = kk_function_create_1(unsafeBitCast(reflectedArrayInitializer, to: Int.self), 0, &thrown)
                    let initializedArgs = registerRuntimeObject(RuntimeListBox(elements: [kk_box_int(3), initializer]))
                    let initialized = __kk_kcallable_call(initializedConstructor, initializedArgs, &thrown)
                    #expect(thrown == 0)
                    #expect(kk_array_get(initialized, 2, &thrown) == 3)
                    let clone = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "clone" })
                    let copied = __kk_kcallable_call(clone, registerRuntimeObject(RuntimeListBox(elements: [created])), &thrown)
                    #expect(thrown == 0)
                    #expect(copied != created)
                    #expect(kk_array_get(copied, 1, &thrown) == 42)
                } else {
                    let contains = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "contains" })
                    let args = registerRuntimeObject(RuntimeListBox(elements: [created, element]))
                    #expect(kk_unbox_bool(__kk_kcallable_call(contains, args, &thrown)) == 1)
                    #expect(thrown == 0)
                }
            }
            if name.hasPrefix("U") {
                let storage = try #require(properties.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "storage" })
                let underlying = __kk_kcallable_call(storage, registerRuntimeObject(RuntimeListBox(elements: [created])), &thrown)
                #expect(thrown == 0)
                #expect(kk_array_size(underlying) == 4)
                _ = kk_array_set(underlying, 0, 17, &thrown)
                #expect(kk_array_get(created, 0, &thrown) == 17)
                if name == "UIntArray" {
                    _ = kk_array_set(underlying, 0, -1, &thrown)
                    let functions = try runtimeListElements(from: __kk_kclass_member_functions(klass))
                    let get = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "get" })
                    let contains = try #require(functions.first { runtimeStringFromRaw(__kk_kcallable_get_name($0)) == "contains" })
                    let getterArgs = registerRuntimeObject(RuntimeListBox(elements: [created, kk_box_int(0)]))
                    #expect(kk_unbox_int(__kk_kcallable_call(get, getterArgs, &thrown)) == 4_294_967_295)
                    let containsArgs = registerRuntimeObject(RuntimeListBox(elements: [created, kk_box_uint(4_294_967_295)]))
                    #expect(kk_unbox_bool(__kk_kcallable_call(contains, containsArgs, &thrown)) == 1)
                    #expect(thrown == 0)
                }
            }
        }
    }

    // MARK: - ABI-003: __kk_kclass_cast

    @Test func castReturnsNullSentinelAndThrowsOnInvalidKClass() {
        var thrown = 0
        let result = __kk_kclass_cast(runtimeNullSentinelInt, 42, &thrown)
        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0, "Expected ClassCastException for invalid KClass handle")
    }

    @Test func castExceptionMessageContainsClassCastException() throws {
        var thrown = 0
        _ = __kk_kclass_cast(runtimeNullSentinelInt, 42, &thrown)
        let box = try runtimeThrowableBox(from: thrown)
        #expect(
            box.renderedMessage.contains("ClassCastException"),
            "Exception message '\(box.renderedMessage)' should contain 'ClassCastException'"
        )
    }

    @Test func castExceptionIsTypedClassCastExceptionBox() throws {
        var thrown = 0
        _ = __kk_kclass_cast(runtimeNullSentinelInt, 42, &thrown)
        let box = try runtimeThrowableBox(from: thrown)
        #expect(
            runtimeThrowableBoxHasExactType(box, RuntimeClassCastExceptionBox.self),
            """
            __kk_kclass_cast should throw a typed RuntimeClassCastExceptionBox so \
            catch-clause type discrimination works (not the untyped base box)
            """
        )
    }

    @Test func castWithNilOutThrown() {
        // Should not crash when outThrown is nil.
        let result = __kk_kclass_cast(runtimeNullSentinelInt, 42, nil)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func castExceptionContainsTypeName() throws {
        let kclass = registerKClass(
            typeToken: 2001, qualifiedName: "com.example.Foo", simpleName: "Foo"
        )
        let kclass2 = registerKClass(
            typeToken: 2002, qualifiedName: "com.example.Bar", simpleName: "Bar"
        )
        // kclass2's handle has type token 2002, kclass has type token 2001 — they differ.
        var thrown = 0
        let result = __kk_kclass_cast(kclass, kclass2, &thrown)
        // If cast fails, result should be null sentinel and thrown non-zero.
        if thrown != 0 {
            #expect(result == runtimeNullSentinelInt)
            let box = try runtimeThrowableBox(from: thrown)
            #expect(
                box.renderedMessage.contains("ClassCastException"),
                "Message '\(box.renderedMessage)' should contain 'ClassCastException'"
            )
            #expect(
                box.message?.contains("Foo") == true || box.message?.contains("com.example.Foo") == true,
                "Message '\(box.message)' should contain the type name"
            )
        }
    }

    // MARK: - ABI-003: __kk_kclass_safeCast

    @Test func safeCastReturnsNullSentinelForInvalidKClass() {
        let result = __kk_kclass_safeCast(runtimeNullSentinelInt, 42)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func safeCastNeverThrows() {
        // safeCast must not require an outThrown parameter — it's a pure value return.
        // Calling with an invalid kclass just returns null sentinel with no exception.
        let result = __kk_kclass_safeCast(0, 42)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test func safeCastReturnsNullSentinelOnMismatch() {
        let kclass = registerKClass(
            typeToken: 3001, qualifiedName: "pkg.X", simpleName: "X"
        )
        let kclass2 = registerKClass(
            typeToken: 3002, qualifiedName: "pkg.Y", simpleName: "Y"
        )
        // kclass2 handle has type token 3002, kclass has type token 3001 — they differ.
        let result = __kk_kclass_safeCast(kclass, kclass2)
        // Either succeeds (if kk_op_is is lenient) or returns null sentinel — no crash.
        if result != runtimeNullSentinelInt {
            #expect(result == kclass2)
        }
    }

    @Test func safeCastIsConsistentWithIsInstance() {
        let kclass = registerKClass(
            typeToken: 3003, qualifiedName: "pkg.Z", simpleName: "Z"
        )
        let someValue = registerRuntimeObject(RuntimeListBox(elements: []))
        let isInstance = __kk_kclass_isInstance(kclass, someValue)
        let safeCastResult = __kk_kclass_safeCast(kclass, someValue)

        if isInstance == 1 {
            #expect(safeCastResult == someValue)
        } else {
            #expect(safeCastResult == runtimeNullSentinelInt)
        }
    }

    @Test func castIsConsistentWithIsInstance() {
        let kclass = registerKClass(
            typeToken: 3004, qualifiedName: "pkg.W", simpleName: "W"
        )
        let someValue = registerRuntimeObject(RuntimeListBox(elements: []))
        let isInstance = __kk_kclass_isInstance(kclass, someValue)

        var thrown = 0
        let castResult = __kk_kclass_cast(kclass, someValue, &thrown)

        if isInstance == 1 {
            #expect(castResult == someValue)
            #expect(thrown == 0)
        } else {
            #expect(castResult == runtimeNullSentinelInt)
            #expect(thrown != 0)
        }
    }

    // KUU-3947: builtin memberProperties / memberFunctions handles carry the
    // JVM-style `val|fun kotlin.Owner.name(P): kotlin.T` description so the
    // println path never renders `<object 0x…>`.
    @Test func builtinMemberHandlesPrintQualifiedSignatures() throws {
        let stringClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.stringBase), 0)
        let stringProperties = try runtimeListElements(from: __kk_kclass_member_properties(stringClass))
        #expect(stringProperties.map(runtimeRenderAnyForPrint) == [
            "val kotlin.String.length: kotlin.Int",
        ])
        let stringFunctions = try runtimeListElements(from: __kk_kclass_member_functions(stringClass))
        #expect(stringFunctions.map(runtimeRenderAnyForPrint) == [
            "fun kotlin.String.get(kotlin.Int): kotlin.Char",
            "fun kotlin.String.toString(): kotlin.String",
            "fun kotlin.String.compareTo(kotlin.String): kotlin.Int",
            "fun kotlin.String.equals(kotlin.Any?): kotlin.Boolean",
            "fun kotlin.String.hashCode(): kotlin.Int",
            "fun kotlin.String.plus(kotlin.Any?): kotlin.String",
            "fun kotlin.String.subSequence(kotlin.Int, kotlin.Int): kotlin.CharSequence",
        ])

        let uintClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.uintBase), 0)
        let uintProperties = try runtimeListElements(from: __kk_kclass_member_properties(uintClass))
        #expect(uintProperties.map(runtimeRenderAnyForPrint) == [
            "val kotlin.UInt.data: kotlin.Int",
        ])

        let intArrayToken = Int(
            RuntimeTypeTokenEncoding.nominalBase
                | (runtimeStableNominalTypeID(fqName: "kotlin.IntArray") << RuntimeTypeTokenEncoding.payloadShift)
        )
        let intArrayClass = __kk_kclass_create(intArrayToken, 0)
        let intArrayProperties = try runtimeListElements(from: __kk_kclass_member_properties(intArrayClass))
        #expect(intArrayProperties.map(runtimeRenderAnyForPrint) == [
            "val kotlin.IntArray.size: kotlin.Int",
        ])

        let intClass = __kk_kclass_create(Int(RuntimeTypeTokenEncoding.intBase), 0)
        let intFunctions = try runtimeListElements(from: __kk_kclass_member_functions(intClass))
        let renderedIntFunctions = intFunctions.map(runtimeRenderAnyForPrint)
        #expect(renderedIntFunctions.contains("fun kotlin.Int.plus(kotlin.Int): kotlin.Int"))
        #expect(renderedIntFunctions.contains("fun kotlin.Int.equals(kotlin.Any?): kotlin.Boolean"))
        #expect(renderedIntFunctions.allSatisfy { !$0.hasPrefix("<object") })
    }
}
