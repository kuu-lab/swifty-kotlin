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

// Foundation bridge handles share GC state and must not race with runtime resets.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeAppleFoundationTests {
    @Test func foundationPointersRetainTheirCPointerType() throws {
        let array = kk_array_new(3)
        defer { _ = runtimeReleaseObject(array) }
        _ = kk_array_tag_type(array, Int(runtimeStableNominalTypeID(fqName: "kotlin.ByteArray")))
        let pinned = kk_pin_object(array)
        defer { _ = kk_unpin_object(pinned) }
        var thrown = 0
        let destination = __kk_foundation_pinned_bytes_address(pinned, 0, &thrown)
        try #require(thrown == 0)
        defer { _ = runtimeReleaseObject(destination) }
        let data = __kk_foundation_data_create(destination, 3, 0, 0, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(data) }
        let source = __kk_foundation_data_bytes(data, &thrown)
        try #require(thrown == 0)
        defer { _ = runtimeReleaseObject(source) }
        let copied = __kk_foundation_memcpy(destination, source, 3, &thrown)
        try #require(thrown == 0)
        let advanced = __kk_foundation_byte_pointer_add(destination, 1, &thrown)
        try #require(thrown == 0)
        defer { _ = runtimeReleaseObject(advanced) }
        let pointerType = nominalTypeToken(for: "kotlinx.cinterop.CPointer")
        let otherType = nominalTypeToken(for: "kotlinx.cinterop.MemScope")
        for pointer in [destination, source, copied, advanced] {
            #expect(kk_op_is(pointer, pointerType) == 1)
            #expect(kk_op_is(pointer, otherType) == 0)
            #expect(kk_op_cast(pointer, pointerType, &thrown) == pointer)
            #expect(thrown == 0)
        }
    }

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
        try bytePointerOffsetsAcceptAliasTargetsAndRejectOtherStorage()
    }

    private func bytePointerOffsetsAcceptAliasTargetsAndRejectOtherStorage() throws {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 3)
        defer { bytes.deallocate() }
        bytes.initialize(repeating: 65, count: 3)
        for name in ["ByteVar", "ByteVarOf", "UByteVar", "UByteVarOf", "IntVar", "BooleanVar"] {
            let typeID = runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.\(name)")
            let pointer = registerRuntimeObject(RuntimeCPointerBox(
                address: UInt(bitPattern: bytes), pointeeTypeID: typeID))
            defer { _ = runtimeReleaseObject(pointer) }
            var thrown = 0
            let result = __kk_foundation_byte_pointer_add(pointer, 2, &thrown)
            if name == "IntVar" || name == "BooleanVar" {
                #expect(thrown != 0)
                _ = runtimeReleaseObject(thrown)
            } else {
                try #require(thrown == 0)
                let shifted = try #require(resolveCPointerBox(from: result))
                #expect(shifted.address == UInt(bitPattern: bytes.advanced(by: 2)))
                #expect(shifted.pointeeTypeID == typeID)
                #expect(UnsafePointer<UInt8>(bitPattern: shifted.address)?.pointee == 65)
                _ = runtimeReleaseObject(result)
            }
        }
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

    @Test func nsDataCompressionRoundTripsAndMutableDataCreateLength() throws {
        let payload = Array("Compress me, please!".utf8)
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: payload.count)
        defer { bytes.deallocate() }
        bytes.initialize(from: payload, count: payload.count)
        let pointer = registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: bytes)))
        defer { _ = runtimeReleaseObject(pointer) }
        var thrown = 0
        let token = __kk_foundation_data_create(pointer, payload.count, 0, 0, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(token) }

        // NSDataCompressionAlgorithmZlib == 3 (NSData.h NS_ENUM order).
        let compressedBoxed = __kk_foundation_data_compressed(token, 3, &thrown)
        try #require(thrown == 0)
        #expect(compressedBoxed != runtimeNullSentinelInt)
        let compressedHandle = kk_unbox_long(compressedBoxed)
        defer { runtimeForeignResourceDiscardUnattached(compressedHandle) }
        let compressed = try #require(runtimeForeignResource(compressedHandle, as: NSData.self))
        #expect(compressed.length == 22)
        let expectedZlib: [UInt8] = [0x73, 0xce, 0xcf, 0x2d, 0x28, 0x4a, 0x2d, 0x2e,
                                      0x56, 0xc8, 0x4d, 0xd5, 0x51, 0x28, 0xc8, 0x49,
                                      0x4d, 0x2c, 0x4e, 0x55, 0x04, 0x00]
        #expect(Array(compressed as Data) == expectedZlib)

        let decompressedBoxed = __kk_foundation_data_decompressed(compressedHandle, 3, &thrown)
        try #require(thrown == 0)
        #expect(decompressedBoxed != runtimeNullSentinelInt)
        let decompressedHandle = kk_unbox_long(decompressedBoxed)
        defer { runtimeForeignResourceDiscardUnattached(decompressedHandle) }
        let decompressed = try #require(runtimeForeignResource(decompressedHandle, as: NSData.self))
        #expect(Array(decompressed as Data) == payload)

        // LZFSE=0, LZ4=1, LZMA=2 also round-trip through the same bridges.
        for algorithm in 0...2 {
            let compressedOther = __kk_foundation_data_compressed(token, algorithm, &thrown)
            try #require(thrown == 0)
            #expect(compressedOther != runtimeNullSentinelInt)
            let otherHandle = kk_unbox_long(compressedOther)
            let restored = __kk_foundation_data_decompressed(otherHandle, algorithm, &thrown)
            try #require(thrown == 0)
            #expect(restored != runtimeNullSentinelInt)
            let restoredHandle = kk_unbox_long(restored)
            let restoredData = try #require(runtimeForeignResource(restoredHandle, as: NSData.self))
            #expect(Array(restoredData as Data) == payload)
            runtimeForeignResourceDiscardUnattached(otherHandle)
            runtimeForeignResourceDiscardUnattached(restoredHandle)
        }

        // An undefined algorithm value throws rather than corrupting state.
        _ = __kk_foundation_data_compressed(token, 99, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
        thrown = 0

        // Decompressing uncompressed bytes follows the nullable API: nil, no throw.
        let invalidDecompressed = __kk_foundation_data_decompressed(token, 3, &thrown)
        #expect(thrown == 0)
        #expect(invalidDecompressed == runtimeNullSentinelInt)

        // +dataWithLength: zero-fills and reports the requested length.
        let mutableBoxed = __kk_foundation_mutable_data_create_length(8, &thrown)
        try #require(thrown == 0)
        #expect(mutableBoxed != runtimeNullSentinelInt)
        let mutableHandle = kk_unbox_long(mutableBoxed)
        defer { runtimeForeignResourceDiscardUnattached(mutableHandle) }
        let mutable = try #require(runtimeForeignResource(mutableHandle, as: NSMutableData.self))
        #expect(mutable.length == 8)
        let mutableBytes = mutable.bytes
        for index in 0..<mutable.length {
            #expect(mutableBytes.load(fromByteOffset: index, as: UInt8.self) == 0)
        }

        // A negative length (e.g. a ULong above Int64.max) is rejected, not crashed.
        _ = __kk_foundation_mutable_data_create_length(-1, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
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

    // MARK: - KUU-4036 value-type Foundation bridges

    @Test func nsDateArithmeticComparisonFactoriesAndDistantDates() throws {
        var thrown = 0
        // +dateWithTimeIntervalSince1970:0 is the Unix epoch.
        let epoch = __kk_foundation_date_factory_since1970(kk_double_to_bits(0), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(epoch) }
        #expect(runtimeForeignResource(epoch, as: NSDate.self)?.timeIntervalSince1970 == 0)
        // kind 0 = since1970, kind 2 = sinceReferenceDate (2001-01-01).
        #expect(kk_bits_to_double(__kk_foundation_date_interval(epoch, 0, &thrown)) == 0)
        #expect(kk_bits_to_double(__kk_foundation_date_interval(epoch, 2, &thrown)) == -978307200.0)

        // init(timeIntervalSinceReferenceDate:) stores reference-relative seconds.
        let reference = __kk_foundation_date_create_reference(kk_double_to_bits(42.5), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(reference) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(reference, 2, &thrown)) == 42.5)

        // dateByAddingTimeInterval: and init(timeInterval:sinceDate:) share the math.
        let later = __kk_foundation_date_add(epoch, kk_double_to_bits(10), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(later) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(later, 0, &thrown)) == 10)
        let offset = __kk_foundation_date_create_since(kk_double_to_bits(5), epoch, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(offset) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(offset, 0, &thrown)) == 5)
        let factorySince = __kk_foundation_date_factory_since(kk_double_to_bits(7), epoch, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(factorySince) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(factorySince, 0, &thrown)) == 7)

        // compare:/isEqualToDate:/timeIntervalSinceDate:/earlierDate:/laterDate:.
        #expect(__kk_foundation_date_compare(epoch, later, &thrown) == -1)
        #expect(__kk_foundation_date_compare(later, epoch, &thrown) == 1)
        #expect(__kk_foundation_date_compare(epoch, epoch, &thrown) == 0)
        #expect(__kk_foundation_date_is_equal(epoch, epoch, &thrown) == 1)
        #expect(__kk_foundation_date_is_equal(epoch, later, &thrown) == 0)
        #expect(__kk_foundation_date_is_equal(epoch, runtimeNullSentinelInt, &thrown) == 0)
        #expect(kk_bits_to_double(__kk_foundation_date_interval_since(later, epoch, &thrown)) == 10)
        let earliest = __kk_foundation_date_extreme(later, epoch, 0, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(earliest) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(earliest, 0, &thrown)) == 0)
        let latest = __kk_foundation_date_extreme(epoch, later, 1, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(latest) }
        #expect(kk_bits_to_double(__kk_foundation_date_interval(latest, 0, &thrown)) == 10)

        // now/distantPast/distantFuture/description.
        let now = __kk_foundation_date_now(&thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(now) }
        let past = __kk_foundation_date_distant(0, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(past) }
        let future = __kk_foundation_date_distant(1, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(future) }
        #expect(__kk_foundation_date_compare(past, future, &thrown) == -1)
        #expect(__kk_foundation_date_compare(now, past, &thrown) == 1)
        #expect(__kk_foundation_date_compare(now, future, &thrown) == -1)
        let description = __kk_foundation_date_description(epoch, &thrown)
        try #require(thrown == 0)
        #expect(runtimeStringFromRaw(description)?.isEmpty == false)

        // Stale/invalid tokens throw instead of dereferencing garbage.
        let doomed = runtimeForeignResourceCreate(NSDate())
        runtimeForeignResourceDiscardUnattached(doomed)
        thrown = 0
        _ = __kk_foundation_date_interval(doomed, 0, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
        thrown = 0
        _ = __kk_foundation_date_interval_since(epoch, doomed, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
    }

    @Test func nsDateFormatterFormatParseStylesAndObjectSlots() throws {
        var thrown = 0
        let formatterToken = __kk_foundation_date_formatter_create(&thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(formatterToken) }

        // dateFormat round-trip; nil clears it (the overlay vends "" for an
        // unset format where ObjC reports nil, so the bridge maps it back).
        _ = __kk_foundation_date_formatter_set_date_format(
            formatterToken, runtimeMakeStringRaw("yyyy-MM-dd"), &thrown)
        try #require(thrown == 0)
        #expect(runtimeStringFromRaw(
            __kk_foundation_date_formatter_date_format(formatterToken, &thrown)) == "yyyy-MM-dd")
        _ = __kk_foundation_date_formatter_set_date_format(
            formatterToken, runtimeNullSentinelInt, &thrown)
        try #require(thrown == 0)
        #expect(__kk_foundation_date_formatter_date_format(formatterToken, &thrown)
            == runtimeNullSentinelInt)

        // isLenient under the default formatter behavior.
        #expect(__kk_foundation_date_formatter_bool(formatterToken, 0, &thrown) == 0)
        _ = __kk_foundation_date_formatter_set_bool(formatterToken, 0, 1, &thrown)
        #expect(__kk_foundation_date_formatter_bool(formatterToken, 0, &thrown) == 1)
        _ = __kk_foundation_date_formatter_set_bool(formatterToken, 0, 0, &thrown)

        // stringFromDate:/dateFromString: round-trip with an explicit format,
        // pinned to GMT so expectations do not depend on the host time zone.
        let epoch = __kk_foundation_date_factory_since1970(kk_double_to_bits(0), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(epoch) }
        let gmtToken = __kk_foundation_timezone_for_seconds_from_gmt(0, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(gmtToken) }
        _ = __kk_foundation_date_formatter_set_object(formatterToken, 1, gmtToken, &thrown)
        try #require(thrown == 0)
        _ = __kk_foundation_date_formatter_set_date_format(
            formatterToken, runtimeMakeStringRaw("yyyy-MM-dd"), &thrown)
        try #require(thrown == 0)
        #expect(runtimeStringFromRaw(
            __kk_foundation_date_formatter_string_from_date(formatterToken, epoch, &thrown))
            == "1970-01-01")
        let parsedBoxed = __kk_foundation_date_formatter_date_from_string(
            formatterToken, runtimeMakeStringRaw("1970-01-02"), &thrown)
        try #require(thrown == 0)
        try #require(parsedBoxed != runtimeNullSentinelInt)
        let parsed = kk_unbox_long(parsedBoxed)
        defer { runtimeForeignResourceDiscardUnattached(parsed) }
        #expect(kk_bits_to_double(
            __kk_foundation_date_interval(parsed, 0, &thrown)) == 86400)
        #expect(__kk_foundation_date_formatter_date_from_string(
            formatterToken, runtimeMakeStringRaw("not a date"), &thrown)
            == runtimeNullSentinelInt)

        // kind 0 = dateStyle, 1 = timeStyle (kind 2 = formatterBehavior is
        // covered separately: 10.0 behavior legitimately changes how locale,
        // isLenient and dateFormat behave, matching NSDateFormatter itself).
        _ = __kk_foundation_date_formatter_set_style(formatterToken, 0, 2, &thrown)
        _ = __kk_foundation_date_formatter_set_style(formatterToken, 1, 3, &thrown)
        #expect(__kk_foundation_date_formatter_style(formatterToken, 0, &thrown) == 2)
        #expect(__kk_foundation_date_formatter_style(formatterToken, 1, &thrown) == 3)

        // +localizedStringFromDate:dateStyle:timeStyle: and
        // +dateFormatFromTemplate:options:locale:.
        #expect(runtimeStringFromRaw(__kk_foundation_date_formatter_localized_string(
            epoch, 2, 3, &thrown))?.isEmpty == false)
        #expect(runtimeStringFromRaw(__kk_foundation_date_formatter_format_from_template(
            runtimeMakeStringRaw("yMMMd"), 0, runtimeNullSentinelInt, &thrown))?.isEmpty == false)

        // locale/timeZone object slots round-trip boxed foreign tokens.
        let localeToken = __kk_foundation_locale_create_identifier(
            runtimeMakeStringRaw("en_US"), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(localeToken) }
        _ = __kk_foundation_date_formatter_set_object(formatterToken, 0, localeToken, &thrown)
        try #require(thrown == 0)
        let localeBoxed = __kk_foundation_date_formatter_object(formatterToken, 0, &thrown)
        try #require(thrown == 0)
        try #require(localeBoxed != runtimeNullSentinelInt)
        let readLocale = kk_unbox_long(localeBoxed)
        defer { runtimeForeignResourceDiscardUnattached(readLocale) }
        #expect(runtimeForeignResource(readLocale, as: NSLocale.self)?.languageCode == "en")

        let zoneToken = __kk_foundation_timezone_for_seconds_from_gmt(32400, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(zoneToken) }
        _ = __kk_foundation_date_formatter_set_object(formatterToken, 1, zoneToken, &thrown)
        try #require(thrown == 0)
        let zoneBoxed = __kk_foundation_date_formatter_object(formatterToken, 1, &thrown)
        try #require(zoneBoxed != runtimeNullSentinelInt)
        let readZone = kk_unbox_long(zoneBoxed)
        defer { runtimeForeignResourceDiscardUnattached(readZone) }
        #expect(runtimeForeignResource(readZone, as: NSTimeZone.self)?.secondsFromGMT == 32400)

        // Clearing the locale reports the formatter's effective (current)
        // locale again: the Swift overlay never vends nil for Formatter.locale.
        _ = __kk_foundation_date_formatter_set_object(formatterToken, 0, -1, &thrown)
        try #require(thrown == 0)
        let clearedLocaleBoxed = __kk_foundation_date_formatter_object(formatterToken, 0, &thrown)
        try #require(clearedLocaleBoxed != runtimeNullSentinelInt)
        let clearedLocale = kk_unbox_long(clearedLocaleBoxed)
        defer { runtimeForeignResourceDiscardUnattached(clearedLocale) }
        #expect(runtimeForeignResource(clearedLocale, as: NSLocale.self) != nil)

        // formatterBehavior raw values round-trip on a dedicated formatter.
        let behaviorToken = __kk_foundation_date_formatter_create(&thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(behaviorToken) }
        _ = __kk_foundation_date_formatter_set_style(behaviorToken, 2, 1000, &thrown)
        #expect(__kk_foundation_date_formatter_style(behaviorToken, 2, &thrown) == 1000)
        _ = __kk_foundation_date_formatter_set_style(behaviorToken, 2, 1040, &thrown)
        #expect(__kk_foundation_date_formatter_style(behaviorToken, 2, &thrown) == 1040)
        _ = __kk_foundation_date_formatter_set_style(behaviorToken, 2, 0, &thrown)
        #expect(__kk_foundation_date_formatter_style(behaviorToken, 2, &thrown) == 0)

        // Invalid formatter tokens throw.
        thrown = 0
        _ = __kk_foundation_date_formatter_style(0x7FFF_FFFE, 0, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
    }

    @Test func nsTimeZoneLocaleAndUUIDBridges() throws {
        var thrown = 0
        let tokyo = __kk_foundation_timezone_create_name(
            runtimeMakeStringRaw("Asia/Tokyo"), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(tokyo) }
        #expect(runtimeStringFromRaw(
            __kk_foundation_timezone_name(tokyo, &thrown)) == "Asia/Tokyo")
        #expect(__kk_foundation_timezone_seconds_from_gmt(tokyo, &thrown) == 32400)
        let epoch = __kk_foundation_date_factory_since1970(kk_double_to_bits(0), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(epoch) }
        #expect(__kk_foundation_timezone_seconds_from_gmt_for_date(tokyo, epoch, &thrown) == 32400)
        #expect(runtimeStringFromRaw(
            __kk_foundation_timezone_abbreviation_for_date(tokyo, epoch, &thrown)) == "JST")

        // +timeZoneWithName:/+timeZoneWithAbbreviation: vend boxed tokens;
        // unknown names vend the null sentinel.
        let namedBoxed = __kk_foundation_timezone_with_name(
            runtimeMakeStringRaw("Asia/Tokyo"), &thrown)
        try #require(thrown == 0)
        try #require(namedBoxed != runtimeNullSentinelInt)
        let named = kk_unbox_long(namedBoxed)
        defer { runtimeForeignResourceDiscardUnattached(named) }
        #expect(__kk_foundation_timezone_is_equal(tokyo, named, &thrown) == 1)
        #expect(__kk_foundation_timezone_with_name(
            runtimeMakeStringRaw("KUU4036/NotAZone"), &thrown) == runtimeNullSentinelInt)
        let abbrev = __kk_foundation_timezone_with_abbreviation(
            runtimeMakeStringRaw("JST"), &thrown)
        #expect(abbrev == runtimeNullSentinelInt || kk_unbox_long(abbrev) >= 0)
        let fixed = __kk_foundation_timezone_for_seconds_from_gmt(3600, &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(fixed) }
        #expect(__kk_foundation_timezone_seconds_from_gmt(fixed, &thrown) == 3600)
        #expect(__kk_foundation_timezone_is_equal(tokyo, fixed, &thrown) == 0)

        // localTimeZone/systemTimeZone vend valid zones on this host.
        for factory in [__kk_foundation_timezone_local, __kk_foundation_timezone_system] {
            let zone = factory(&thrown)
            try #require(thrown == 0)
            defer { runtimeForeignResourceDiscardUnattached(zone) }
            #expect(runtimeForeignResource(zone, as: NSTimeZone.self) != nil)
            #expect(runtimeStringFromRaw(__kk_foundation_timezone_name(zone, &thrown))?.isEmpty == false)
        }

        // NSLocale identifier/language/country plus current/autoupdating.
        let locale = __kk_foundation_locale_create_identifier(
            runtimeMakeStringRaw("en_US"), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(locale) }
        #expect(runtimeStringFromRaw(
            __kk_foundation_locale_identifier(locale, &thrown))?.hasPrefix("en") == true)
        #expect(runtimeStringFromRaw(
            __kk_foundation_locale_language_code(locale, &thrown)) == "en")
        #expect(runtimeStringFromRaw(
            __kk_foundation_locale_country_code(locale, &thrown)) == "US")
        for factory in [__kk_foundation_locale_current, __kk_foundation_locale_autoupdating,
                        { __kk_foundation_locale_with_identifier(
                            runtimeMakeStringRaw("ja_JP"), $0) }] {
            let produced = factory(&thrown)
            try #require(thrown == 0)
            defer { runtimeForeignResourceDiscardUnattached(produced) }
            #expect(runtimeForeignResource(produced, as: NSLocale.self) != nil)
            #expect(runtimeStringFromRaw(
                __kk_foundation_locale_identifier(produced, &thrown))?.isEmpty == false)
        }

        // NSUUID vends a 36-char hyphenated UUIDString.
        let uuid = __kk_foundation_uuid_create(&thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(uuid) }
        let uuidString = runtimeStringFromRaw(__kk_foundation_uuid_string(uuid, &thrown))
        try #require(uuidString?.count == 36)
        #expect(uuidString?.filter { $0 == "-" }.count == 4)
    }

    @Test func nsUserDefaultsSuiteScalarsObjectsAndDomains() throws {
        var thrown = 0
        let suite = "KSwiftK-KUU4036-\(UUID().uuidString)"
        let defaults = __kk_foundation_defaults_create_suite(
            runtimeMakeStringRaw(suite), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(defaults) }
        #expect(runtimeForeignResource(defaults, as: UserDefaults.self) != nil)

        // Missing keys read as the Foundation defaults: nil/0/false.
        #expect(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("absent"), &thrown) == runtimeNullSentinelInt)
        try #require(thrown == 0)
        #expect(__kk_foundation_defaults_string_for_key(
            defaults, runtimeMakeStringRaw("absent"), &thrown) == runtimeNullSentinelInt)
        #expect(__kk_foundation_defaults_bool_for_key(
            defaults, runtimeMakeStringRaw("absent"), &thrown) == 0)
        #expect(__kk_foundation_defaults_integer_for_key(
            defaults, runtimeMakeStringRaw("absent"), &thrown) == 0)
        #expect(kk_bits_to_double(__kk_foundation_defaults_double_for_key(
            defaults, runtimeMakeStringRaw("absent"), &thrown)) == 0)

        // Scalar setters/getters round-trip through real UserDefaults.
        _ = __kk_foundation_defaults_set_bool(defaults, 1, runtimeMakeStringRaw("flag"), &thrown)
        #expect(__kk_foundation_defaults_bool_for_key(
            defaults, runtimeMakeStringRaw("flag"), &thrown) == 1)
        _ = __kk_foundation_defaults_set_integer(defaults, 42, runtimeMakeStringRaw("count"), &thrown)
        #expect(__kk_foundation_defaults_integer_for_key(
            defaults, runtimeMakeStringRaw("count"), &thrown) == 42)
        _ = __kk_foundation_defaults_set_double(
            defaults, kk_double_to_bits(2.5), runtimeMakeStringRaw("ratio"), &thrown)
        #expect(kk_bits_to_double(__kk_foundation_defaults_double_for_key(
            defaults, runtimeMakeStringRaw("ratio"), &thrown)) == 2.5)
        _ = __kk_foundation_defaults_set_float(
            defaults, kk_float_to_bits(Float(1.5)), runtimeMakeStringRaw("level"), &thrown)
        #expect(kk_bits_to_float(__kk_foundation_defaults_float_for_key(
            defaults, runtimeMakeStringRaw("level"), &thrown)) == Float(1.5))

        // setObject: stores plist strings verbatim; objectForKey reads them back.
        _ = __kk_foundation_defaults_set_object(
            defaults, runtimeMakeStringRaw("hello"), runtimeMakeStringRaw("greeting"), &thrown)
        try #require(thrown == 0)
        let greeting = __kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("greeting"), &thrown)
        try #require(thrown == 0)
        #expect(runtimeStringFromRaw(greeting) == "hello")
        #expect(runtimeStringFromRaw(__kk_foundation_defaults_string_for_key(
            defaults, runtimeMakeStringRaw("greeting"), &thrown)) == "hello")

        // objectForKey surfaces scalars as their Kotlin box kinds: bool stays
        // bool (CFBoolean is checked before NSNumber), integers stay long.
        #expect(kk_unbox_bool(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("flag"), &thrown)) == 1)
        #expect(kk_unbox_long(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("count"), &thrown)) == 42)
        #expect(kk_unbox_double(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("ratio"), &thrown))
            == kk_double_to_bits(2.5))
        #expect(kk_unbox_float(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("level"), &thrown))
            == kk_float_to_bits(Float(1.5)))

        // A Kotlin list plist round-trips as a Kotlin list of natives.
        let listBox = RuntimeListBox(elements: [
            runtimeMakeStringRaw("a"), kk_box_long(7), kk_box_bool(1),
        ])
        let listRaw = registerRuntimeObject(listBox)
        defer { _ = runtimeReleaseObject(listRaw) }
        _ = __kk_foundation_defaults_set_object(
            defaults, listRaw, runtimeMakeStringRaw("items"), &thrown)
        try #require(thrown == 0)
        let items = __kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("items"), &thrown)
        try #require(thrown == 0)
        let itemsList = runtimeListBox(from: items)
        try #require(itemsList?.elements.count == 3)
        #expect(runtimeStringFromRaw(itemsList?.elements[0] ?? 0) == "a")
        #expect(kk_unbox_long(itemsList?.elements[1] ?? 0) == 7)
        #expect(kk_unbox_bool(itemsList?.elements[2] ?? 0) == 1)

        // A nested null has no plist form: modern CFPrefs validation aborts
        // on NSNull, so the bridge rejects the whole value with a throw.
        let nullList = RuntimeListBox(elements: [runtimeNullSentinelInt])
        let nullListRaw = registerRuntimeObject(nullList)
        defer { _ = runtimeReleaseObject(nullListRaw) }
        thrown = 0
        _ = __kk_foundation_defaults_set_object(
            defaults, nullListRaw, runtimeMakeStringRaw("nullitems"), &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
        thrown = 0

        // setObject:nil removes the key rather than storing NSNull.
        _ = __kk_foundation_defaults_set_object(
            defaults, runtimeNullSentinelInt, runtimeMakeStringRaw("greeting"), &thrown)
        try #require(thrown == 0)
        #expect(__kk_foundation_defaults_object_for_key(
            defaults, runtimeMakeStringRaw("greeting"), &thrown) == runtimeNullSentinelInt)

        // Unsupported values (e.g. a raw pointer box) throw.
        let pointerBox = registerRuntimeObject(RuntimeCPointerBox(address: 0))
        defer { _ = runtimeReleaseObject(pointerBox) }
        thrown = 0
        _ = __kk_foundation_defaults_set_object(
            defaults, pointerBox, runtimeMakeStringRaw("bad"), &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
        thrown = 0

        // dictionaryRepresentation exposes the suite contents as a Kotlin map.
        let representation = __kk_foundation_defaults_dictionary_representation(defaults, &thrown)
        try #require(thrown == 0)
        let map = runtimeMapBox(from: representation)
        try #require(map != nil)
        #expect(map?.keyValues.contains {
            runtimeStringFromRaw($0.legacyRawValue) == "count"
        } == true)

        // registerDefaults feeds objectForKey without forcing the key.
        let registration = RuntimeMapBox(keys: [runtimeMakeStringRaw("fallback")],
                                         values: [runtimeMakeStringRaw("registered")])
        let registrationRaw = registerRuntimeObject(registration)
        defer { _ = runtimeReleaseObject(registrationRaw) }
        _ = __kk_foundation_defaults_register_defaults(defaults, registrationRaw, &thrown)
        try #require(thrown == 0)
        #expect(runtimeStringFromRaw(__kk_foundation_defaults_string_for_key(
            defaults, runtimeMakeStringRaw("fallback"), &thrown)) == "registered")
        // objectIsForced reports false for session-set and registered keys
        // alike on the modern SDK — the bridge forwards the real answer.
        #expect(__kk_foundation_defaults_object_is_forced_for_key(
            defaults, runtimeMakeStringRaw("fallback"), &thrown) == 0)
        #expect(__kk_foundation_defaults_object_is_forced_for_key(
            defaults, runtimeMakeStringRaw("count"), &thrown) == 0)

        // Persistent domains round-trip; volatile/persistent name lists are
        // empty on the modern SDK (the enumeration APIs are unavailable).
        let domain = RuntimeMapBox(keys: [runtimeMakeStringRaw("domainKey")],
                                   values: [kk_box_long(9)])
        let domainRaw = registerRuntimeObject(domain)
        defer { _ = runtimeReleaseObject(domainRaw) }
        _ = __kk_foundation_defaults_set_persistent_domain(
            defaults, domainRaw, runtimeMakeStringRaw("KUU4036Domain"), &thrown)
        try #require(thrown == 0)
        let persisted = __kk_foundation_defaults_persistent_domain_for_name(
            defaults, runtimeMakeStringRaw("KUU4036Domain"), &thrown)
        try #require(thrown == 0)
        try #require(persisted != runtimeNullSentinelInt)
        let persistedMap = runtimeMapBox(from: persisted)
        try #require(persistedMap?.entryValues.count == 1)
        #expect(kk_unbox_long(persistedMap?.entryValues[0].legacyRawValue ?? 0) == 9)
        _ = __kk_foundation_defaults_remove_persistent_domain_for_name(
            defaults, runtimeMakeStringRaw("KUU4036Domain"), &thrown)
        try #require(thrown == 0)
        // removePersistentDomain leaves an empty domain dictionary behind on
        // the modern SDK rather than vending nil.
        let removedDomain = __kk_foundation_defaults_persistent_domain_for_name(
            defaults, runtimeMakeStringRaw("KUU4036Domain"), &thrown)
        try #require(thrown == 0)
        #expect(runtimeMapBox(from: removedDomain)?.keyValues.isEmpty == true)

        let volatileNames = __kk_foundation_defaults_volatile_domain_names(defaults, &thrown)
        try #require(thrown == 0)
        #expect(runtimeListBox(from: volatileNames)?.elements.isEmpty == true)
        let persistentNames = __kk_foundation_defaults_persistent_domain_names(defaults, &thrown)
        try #require(thrown == 0)
        #expect(runtimeListBox(from: persistentNames)?.elements.isEmpty == true)

        // synchronize is a real Bool result; standard defaults also vend.
        #expect([0, 1].contains(
            __kk_foundation_defaults_synchronize(defaults, &thrown)))
        let standard = __kk_foundation_defaults_standard(&thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(standard) }
        #expect(runtimeForeignResource(standard, as: UserDefaults.self) != nil)

        // Invalid handles throw.
        thrown = 0
        _ = __kk_foundation_defaults_bool_for_key(
            0x7FFF_FFFE, runtimeMakeStringRaw("x"), &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
    }

    @Test func nsLogThreadConveniencesAndObjectProbe() throws {
        var thrown = 0
        // NSLog expands the format against boxed Kotlin values; it only
        // writes to stderr, so success is a clean return.
        let argsBox = RuntimeArrayBox(length: 3)
        argsBox.elements = [
            runtimeMakeStringRaw("world"), kk_box_int(42), runtimeNullSentinelInt,
        ]
        let argsRaw = registerRuntimeObject(argsBox)
        defer { _ = runtimeReleaseObject(argsRaw) }
        _ = __kk_foundation_nslog(
            runtimeMakeStringRaw("KUU4036 probe: %@ %d %@ %%"), argsRaw, &thrown)
        try #require(thrown == 0)
        _ = __kk_foundation_nslog(runtimeMakeStringRaw("no specs"), runtimeNullSentinelInt, &thrown)
        try #require(thrown == 0)

        // NSThread conveniences: callstack symbols, isMainThread, sleep.
        let stack = __kk_foundation_thread_callstack(&thrown)
        try #require(thrown == 0)
        let stackList = runtimeListBox(from: stack)
        try #require(stackList != nil && !stackList!.elements.isEmpty)
        #expect(runtimeStringFromRaw(stackList!.elements[0])?.isEmpty == false)
        #expect([0, 1].contains(__kk_foundation_thread_is_main(&thrown)))
        _ = __kk_foundation_thread_sleep(kk_double_to_bits(0.001), &thrown)
        try #require(thrown == 0)

        // -description forwards to the real object's description.
        let date = __kk_foundation_date_factory_since1970(kk_double_to_bits(0), &thrown)
        try #require(thrown == 0)
        defer { runtimeForeignResourceDiscardUnattached(date) }
        #expect(runtimeStringFromRaw(
            __kk_foundation_object_description(date, &thrown))?.isEmpty == false)
        thrown = 0
        _ = __kk_foundation_object_description(0x7FFF_FFFE, &thrown)
        #expect(thrown != 0)
        _ = runtimeReleaseObject(thrown)
        thrown = 0

        // object_probe only resolves tagged foreign tokens; plain longs,
        // strings, collections and null all probe as -1.
        let probeToken = runtimeForeignResourceCreate(NSDate())
        defer { runtimeForeignResourceDiscardUnattached(probeToken) }
        let tagged = probeToken | (Int(1) << 62)
        #expect(__kk_foundation_object_probe(kk_box_long(tagged), &thrown) == probeToken)
        #expect(__kk_foundation_object_probe(kk_box_long(probeToken), &thrown) == -1)
        #expect(__kk_foundation_object_probe(kk_box_long(12345), &thrown) == -1)
        #expect(__kk_foundation_object_probe(runtimeMakeStringRaw("x"), &thrown) == -1)
        #expect(__kk_foundation_object_probe(runtimeNullSentinelInt, &thrown) == -1)
        thrown = 0
    }

}
#endif
