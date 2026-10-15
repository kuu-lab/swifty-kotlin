import Foundation
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeDelegatedPropertyStubCacheTests {
    @Test
    func reusesStubForTheSameDelegatedPropertyIdentity() {
        let identity = "test-delegated-property-\(UUID().uuidString)"
        let nameRaw = makeStringRaw("value")
        let returnTypeRaw = makeStringRaw("String")
        let identityRaw = makeStringRaw(identity)

        let first = kk_kproperty_stub_create_cached(nameRaw, returnTypeRaw, identityRaw)
        let second = kk_kproperty_stub_create_cached(nameRaw, returnTypeRaw, identityRaw)

        #expect(first == second)
    }

    private func makeStringRaw(_ value: String) -> Int {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
                Int(bitPattern: kk_string_from_utf8(pointer, Int32(value.utf8.count)))
            }
        }
    }
}
