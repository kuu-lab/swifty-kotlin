import Foundation
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeLocalDelegatedPropertyStubTests {
    // KUU-2947: a `val/var x by Delegate()` declared inside a function hands
    // getValue/setValue a KProperty0 (KMutableProperty0 for `var`) stub — the
    // JVM's PropertyReference0Impl/MutablePropertyReference0Impl — whose
    // accessor members throw a catchable UnsupportedOperationException.

    private let kProperty0TypeID = Int(kProperty0RuntimeTypeID)
    private let kMutableProperty0TypeID = Int(kMutableProperty0RuntimeTypeID)
    private let kCallableTypeID = Int(kCallableRuntimeTypeID)

    @Test
    func valStubIsKProperty0NotKMutable() {
        let stub = makeStub(isMutable: 0)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty0")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KCallable")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KMutableProperty0")) == 0)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KMutableProperty1")) == 0)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty1")) == 0)
    }

    @Test
    func varStubIsKMutableProperty0AndKProperty0() {
        let stub = makeStub(isMutable: 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KMutableProperty0")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty0")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KMutableProperty")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty")) == 1)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KMutableProperty1")) == 0)
    }

    @Test
    func memberStyleCachedStubIsNotKProperty0() {
        let identity = "member-delegated-\(UUID().uuidString)"
        let stub = kk_kproperty_stub_create_cached(
            makeStringRaw("value"), makeStringRaw("String"), makeStringRaw(identity)
        )
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty0")) == 0)
        #expect(kk_op_is(stub, nominalTypeToken(for: "kotlin.reflect.KProperty")) == 1)
    }

    @Test
    func getInvokeAndSetThrowUnsupportedOperationException() throws {
        let stub = makeStub(isMutable: 0)
        for methodSlot in [0, 2] { // get, invoke
            let fnPtr = kk_itable_lookup_dynamic(stub, kProperty0TypeID, methodSlot)
            #expect(fnPtr != 0)
            let fn = unsafeBitCast(
                fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
            )
            var thrown = 0
            _ = fn(stub, &thrown)
            let throwable = try requireThrownBox(thrown)
            #expect(throwable is RuntimeUnsupportedOperationExceptionBox)
            #expect(kk_op_is(thrown, nominalTypeToken(for: "kotlin.UnsupportedOperationException")) == 1)
        }

        let mutableStub = makeStub(isMutable: 1)
        let setPtr = kk_itable_lookup_dynamic(mutableStub, kMutableProperty0TypeID, 0)
        #expect(setPtr != 0)
        let setFn = unsafeBitCast(
            setPtr, to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        _ = setFn(mutableStub, 0, &thrown)
        #expect(try requireThrownBox(thrown) is RuntimeUnsupportedOperationExceptionBox)
    }

    @Test
    func getDelegateReturnsNullWithoutThrowing() throws {
        let stub = makeStub(isMutable: 0)
        let fnPtr = kk_itable_lookup_dynamic(stub, kProperty0TypeID, 1)
        #expect(fnPtr != 0)
        let fn = unsafeBitCast(
            fnPtr, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        let result = fn(stub, &thrown)
        #expect(thrown == 0)
        #expect(result == runtimeNullSentinelInt)
    }

    @Test
    func callAndCallByThrowUnsupportedOperationException() throws {
        let stub = makeStub(isMutable: 0)
        let emptyArgs = registerRuntimeObject(RuntimeListBox(elements: []))
        var thrown = 0
        _ = __kk_kcallable_call(stub, emptyArgs, &thrown)
        #expect(try requireThrownBox(thrown) is RuntimeUnsupportedOperationExceptionBox)

        thrown = 0
        _ = __kk_kcallable_call_by(stub, 0, &thrown)
        #expect(try requireThrownBox(thrown) is RuntimeUnsupportedOperationExceptionBox)
    }

    @Test
    func getterAndSetterAccessorCallsThrowUnsupportedOperationException() throws {
        let stub = makeStub(isMutable: 1)
        // getter.call() takes no argument; setter.call(value) takes one —
        // matching arity reaches the unsupported-accessor body on the JVM too.
        for (member, argCount) in [(9, 0), (10, 1)] {
            let accessor = __kk_kcallable_get_metadata(stub, member)
            #expect(accessor != 0)
            #expect(accessor != runtimeNullSentinelInt)
            var thrown = 0
            let args = registerRuntimeObject(RuntimeListBox(elements: Array(repeating: 0, count: argCount)))
            _ = __kk_kcallable_call(accessor, args, &thrown)
            #expect(try requireThrownBox(thrown) is RuntimeUnsupportedOperationExceptionBox)
        }
    }

    @Test
    func localStubsAreCachedPerIdentity() {
        let identity = "local-delegated-\(UUID().uuidString)"
        let nameRaw = makeStringRaw("value")
        let returnTypeRaw = makeStringRaw("String")
        let identityRaw = makeStringRaw(identity)
        let first = kk_kproperty_stub_create_local(nameRaw, returnTypeRaw, identityRaw, 0)
        let second = kk_kproperty_stub_create_local(nameRaw, returnTypeRaw, identityRaw, 0)
        #expect(first == second)
    }

    @Test
    func localStubDoesNotCollideWithMemberStubIdentity() {
        let identity = "shared-identity-\(UUID().uuidString)"
        let nameRaw = makeStringRaw("value")
        let returnTypeRaw = makeStringRaw("String")
        let identityRaw = makeStringRaw(identity)
        let member = kk_kproperty_stub_create_cached(nameRaw, returnTypeRaw, identityRaw)
        let local = kk_kproperty_stub_create_local(nameRaw, returnTypeRaw, identityRaw, 0)
        #expect(member != local)
        #expect(kk_op_is(local, nominalTypeToken(for: "kotlin.reflect.KProperty0")) == 1)
        #expect(kk_op_is(member, nominalTypeToken(for: "kotlin.reflect.KProperty0")) == 0)
    }

    private func makeStub(isMutable: Int) -> Int {
        kk_kproperty_stub_create_local(
            makeStringRaw("value"),
            makeStringRaw("String"),
            makeStringRaw("local-delegated-\(UUID().uuidString)"),
            isMutable
        )
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }
}
