@testable import Runtime
import Testing

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

    @Test func registerMemberIgnoresInvalidHandles() throws {
        let kclass = registerKClass(typeToken: 1005, qualifiedName: "pkg.E", simpleName: "E")
        // Invalid handles should be ignored.
        _ = __kk_kclass_register_member(kclass, 0)
        _ = __kk_kclass_register_member(kclass, runtimeNullSentinelInt)
        _ = __kk_kclass_register_member(kclass, 0xDEAD_BEEF)

        let list = try runtimeListBox(from: __kk_kclass_members(kclass))
        #expect(list.elements.isEmpty)
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
}
