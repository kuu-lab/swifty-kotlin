#if os(macOS)
import Foundation
import Darwin
@testable import Runtime
import Testing

// A real SDK InputStream subclass makes the native outpointer identity
// observable. It is test-only; no Kotlin Foundation declaration is replaced.
private final class FoundationGetBufferPointerProbe: InputStream {
    let storage: UnsafeMutablePointer<UInt8>
    var calls = 0
    var bufferAddress: UInt = 0
    var lengthAddress: UInt = 0
    var providesBuffer = true

    init(sampleByte: UInt8 = 42) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: sampleByte)
        super.init(data: Data())
    }
    required init?(coder: NSCoder) { return nil }
    deinit { storage.deinitialize(count: 1); storage.deallocate() }

    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
                            length len: UnsafeMutablePointer<Int>) -> Bool {
        calls += 1
        bufferAddress = UInt(bitPattern: buffer)
        lengthAddress = UInt(bitPattern: len)
        guard providesBuffer else { return false }
        buffer.pointee = storage
        len.pointee = 1
        return true
    }
}

@Suite(.serialized)
struct RuntimeAppleFoundationTests {
    @Test func realNSDataCopiesAndItsLeaseFollowsBoxRelease() throws {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
        defer { bytes.deallocate() }
        bytes.initialize(repeating: 17, count: 3)
        let pointer = registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: bytes)))
        defer { _ = runtimeReleaseObject(pointer) }
        var thrown = 0
        let token = __kk_foundation_data_create(pointer, 3, 0, 0, &thrown)
        try #require(thrown == 0)
        let owner = kk_object_new(1, 0)
        _ = __kk_foundation_attach(owner, token, &thrown)
        try #require(thrown == 0)
        weak var observation: NSData?
        do {
            let real = try #require(runtimeForeignResource(token, as: NSData.self))
            observation = real
            bytes[0] = 99
            #expect((real as Data) == Data([17, 17, 17]))
            #expect(real.isKind(of: NSData.self))
        }
        try #require(runtimeReleaseObject(owner))
        #expect(runtimeForeignResource(token, as: NSData.self) == nil)
        #expect(observation == nil)
    }

    @Test func nativeByteStorageSeesKotlinWritesAndPointerWrites() throws {
        let byteArray = RuntimeArrayBox(length: 3)
        byteArray.elements = [1, 2, 3]
        let address = try #require(byteArray.nativeByteAddress(at: 0))
        #expect(Array(UnsafeBufferPointer(start: address, count: 3)) == [1, 2, 3])
        address[0] = 255
        #expect(byteArray[0] == -1)
        #expect(byteArray.elements == [-1, 2, 3])
        byteArray[1] = 42
        #expect(address[1] == 42)
        byteArray.elements = [0, 7, -128]
        #expect(Array(UnsafeBufferPointer(start: address, count: 3)) == [0, 7, 128])
        byteArray.setValue(9, at: 2, anyFallbackTag: 0)
        #expect(address[2] == 9)
        let ordinary = RuntimeArrayBox(length: 2)
        ordinary.elements = [Int.max, Int.min]
        #expect(ordinary.elements == [Int.max, Int.min])
    }
    @Test func nativeNoCopyStorageAndUnattachedRollbackFollowSDKOwnership() throws {
        let bytes = try #require(malloc(3)?.assumingMemoryBound(to: UInt8.self))
        defer { free(bytes) }
        bytes.initialize(repeating: 17, count: 3)
        let pointer = registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: bytes)))
        defer { _ = runtimeReleaseObject(pointer) }
        var thrown = 0
        let token = __kk_foundation_data_create(pointer, 3, 1, 0, &thrown)
        try #require(thrown == 0)
        weak var observation: NSData?
        do {
            let sdk = try #require(runtimeForeignResource(token, as: NSData.self))
            observation = sdk
            bytes[1] = 99
            #expect((sdk as Data) == Data([17, 99, 17]))
        }
        runtimeForeignResourceDiscardUnattached(token)
        #expect(runtimeForeignResource(token, as: NSData.self) == nil)
        #expect(observation == nil)
        // freeWhenDone false leaves the caller-owned native allocation intact.
        bytes[2] = 42
        #expect(bytes[2] == 42)
        let pending = runtimeForeignResourceCreate(NSObject())
        _ = __kk_foundation_attach(runtimeNullSentinelInt, pending, &thrown)
        #expect(thrown != 0)
        #expect(runtimeForeignResource(pending, as: NSObject.self) == nil)
        _ = runtimeReleaseObject(thrown)
        try getBufferForwardsExactMutableNativeOutputsAndRejectsNullStorage()
    }

    @Test func actualNSErrorUserInfoKeepsOriginalKotlinCauseIdentity() throws {
        let cause = runtimeAllocateIllegalArgumentException(message: "original Kotlin cause")
        defer { _ = runtimeReleaseObject(cause) }
        var thrown = 0
        let token = __kk_foundation_error_create(runtimeMakeStringRaw("Kotlin"), 7,
            runtimeMakeStringRaw("original description"), cause, &thrown)
        try #require(thrown == 0)
        do {
            let sdk = try #require(runtimeForeignResource(token, as: NSError.self))
            #expect(sdk.domain == "Kotlin" && sdk.code == 7)
            #expect(sdk.localizedDescription == "original description")
            let underlying = try #require(sdk.userInfo[NSUnderlyingErrorKey] as? RuntimeFoundationKotlinError)
            #expect(underlying.raw == cause)
        }
        runtimeForeignResourceDiscardUnattached(token)
        #expect(runtimeForeignResource(token, as: NSError.self) == nil)
    }

    private func getBufferForwardsExactMutableNativeOutputsAndRejectsNullStorage() throws {
        let sdk = FoundationGetBufferPointerProbe()
        let token = runtimeForeignResourceCreate(sdk)
        defer { runtimeForeignResourceDiscardUnattached(token) }
        var returnedBuffer: UnsafeMutablePointer<UInt8>? = nil
        var returnedLength = -1
        withUnsafeMutablePointer(to: &returnedBuffer) { bufferAddress in
            withUnsafeMutablePointer(to: &returnedLength) { lengthAddress in
                let bufferArg = registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: bufferAddress)))
                let lengthArg = registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: lengthAddress)))
                let zeroAddress = registerRuntimeObject(RuntimeCPointerBox(address: 0))
                defer {
                    _ = runtimeReleaseObject(bufferArg)
                    _ = runtimeReleaseObject(lengthArg)
                    _ = runtimeReleaseObject(zeroAddress)
                }
                var thrown = 0
                for (buffer, length) in [
                    (runtimeNullSentinelInt, runtimeNullSentinelInt),
                    (runtimeNullSentinelInt, lengthArg),
                    (bufferArg, runtimeNullSentinelInt),
                    (zeroAddress, lengthArg), (bufferArg, zeroAddress),
                ] {
                    let result = __kk_foundation_stream_call(token, 12, buffer, length, &thrown)
                    #expect(kk_unbox_bool(result) == 0 && thrown == 0)
                    #expect(sdk.calls == 0, "Missing native storage must never enter the SDK")
                    #expect(bufferAddress.pointee == nil && lengthAddress.pointee == -1)
                }
                let provided = __kk_foundation_stream_call(token, 12, bufferArg, lengthArg, &thrown)
                #expect(kk_unbox_bool(provided) == 1 && thrown == 0)
                #expect(sdk.calls == 1)
                #expect(sdk.bufferAddress == UInt(bitPattern: bufferAddress))
                #expect(sdk.lengthAddress == UInt(bitPattern: lengthAddress))
                #expect(bufferAddress.pointee == sdk.storage && lengthAddress.pointee == 1)
                #expect(bufferAddress.pointee?.pointee == 42)
                sdk.providesBuffer = false
                bufferAddress.pointee = nil
                lengthAddress.pointee = -1
                let unavailable = __kk_foundation_stream_call(token, 12, bufferArg, lengthArg, &thrown)
                #expect(kk_unbox_bool(unavailable) == 0 && thrown == 0)
                #expect(sdk.calls == 2)
                #expect(bufferAddress.pointee == nil && lengthAddress.pointee == -1)
            }
        }
    }

}
#endif
