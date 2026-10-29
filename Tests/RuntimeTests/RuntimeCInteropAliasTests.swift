@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.all))
struct RuntimeCInteropAliasTests {
    @Test
    func byteVarPointersProduceConcreteVariableTypes() throws {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
        defer { bytes.deallocate() }
        bytes.initialize(from: [255, 0, 65], count: 3)
        let byteVarOf = nominalTypeToken(for: "kotlinx.cinterop.ByteVarOf")
        let intVar = nominalTypeToken(for: "kotlinx.cinterop.IntVar")
        for name in ["ByteVar", "ByteVarOf"] {
            let pointeeTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.\(name)")
            let pointer = registerRuntimeObject(RuntimeCPointerBox(
                address: UInt(bitPattern: bytes), pointeeTypeID: pointeeTypeID))
            let pointed = kk_cpointer_pointed(pointer)
            let indexed = kk_cpointer_get(pointer, kk_box_int(2))
            defer {
                _ = runtimeReleaseObject(indexed)
                _ = runtimeReleaseObject(pointed)
                _ = runtimeReleaseObject(pointer)
            }
            #expect(kk_op_is(pointed, byteVarOf) == 1)
            #expect(kk_op_is(indexed, byteVarOf) == 1)
            #expect(kk_op_is(pointed, intVar) == 0)
            #expect(kk_cvar_byte_load(pointed) == -1)
            #expect(kk_cvar_byte_load(indexed) == 65)
            let roundTrip = kk_cvar_ptr(pointed)
            defer { _ = runtimeReleaseObject(roundTrip) }
            #expect(try #require(resolveCPointerBox(from: roundTrip)).pointeeTypeID == pointeeTypeID)
        }
        let intTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.IntVar")
        let other = registerRuntimeObject(RuntimeCPointerBox(
            address: UInt(bitPattern: bytes), pointeeTypeID: intTypeID))
        let otherPointed = kk_cpointer_pointed(other)
        defer {
            _ = runtimeReleaseObject(otherPointed)
            _ = runtimeReleaseObject(other)
        }
        #expect(kk_op_is(otherPointed, intVar) == 1)
        #expect(kk_op_is(otherPointed, byteVarOf) == 0)
    }
}
