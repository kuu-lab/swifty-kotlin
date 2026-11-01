import Foundation

private let ioDescriptionEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_io_stream_to_string(raw, thrown)
}

private let ioInputCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_close_throwing(raw, thrown)
}

private let ioInputReadEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_read(raw, thrown)
}
private let ioInputAvailableEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_available_throwing(raw, thrown)
}
private let ioInputSkipEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, count, thrown in
    __kk_input_stream_skip(raw, count, thrown)
}
private let ioInputReadBytesEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, bytes, thrown in
    __kk_input_stream_read_bytes(raw, bytes, thrown)
}
private let ioInputReadRangeEntry: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, bytes, offset, count, thrown in
    __kk_input_stream_read_range(raw, bytes, offset, count, thrown)
}
private let ioInputReadAllBytesEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_readAllBytes(raw, thrown)
}
private let ioInputMarkEntry: @convention(c) (Int, Int) -> Int = { raw, readLimit in
    __kk_input_stream_mark(raw, readLimit)
}
private let ioInputResetEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_reset(raw, thrown)
}
private let ioInputMarkSupportedEntry: @convention(c) (Int) -> Int = { raw in
    __kk_input_stream_mark_supported(raw)
}

private let ioOutputCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_output_stream_close_throwing(raw, thrown)
}
private let ioOutputWriteByteEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, value, thrown in
    __kk_output_stream_write_byte(raw, value, thrown)
}
private let ioOutputWriteBytesEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, bytes, thrown in
    __kk_output_stream_write_bytes(raw, bytes, thrown)
}
private let ioOutputWriteRangeEntry: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, bytes, offset, count, thrown in
    __kk_output_stream_write_range(raw, bytes, offset, count, thrown)
}
private let ioOutputFlushEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_output_stream_flush(raw, thrown)
}
private let ioBufferedReaderCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return __kk_buffered_reader_close(raw)
}

private let ioWriterWriteEntry: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, text, thrown in
    __kk_buffered_writer_write(raw, text, thrown)
}
private let ioWriterFlushEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_buffered_writer_flush(raw, thrown)
}
private let ioWriterCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_buffered_writer_close_throwing(raw, thrown)
}

private let ioStringWriterToStringEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return __kk_string_writer_to_string(raw)
}

/// Reader-box vtable entry for `java.io.Reader.read(CharArray, Int, Int)` —
/// forwards to `__kk_reader_read_range`, which resolves the underlying
/// `RuntimeReaderCharSource` (box fast path or Kotlin-reader vtable source).
private let ioReaderReadRangeEntry: @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, bufferRaw, offset, count, thrown in
    __kk_reader_read_range(raw, bufferRaw, offset, count, thrown)
}

/// These slots follow the synthetic java.io stream layouts in
/// `HeaderHelpers+SyntheticJavaIOStreamStubs.swift`. Keep them aligned with
/// those declarations: runtime stream boxes have no generated KTypeInfo
/// vtable, so each allocation installs its bridge implementations directly.
enum RuntimeIoStreamVTableSlot {
    // `java.io.Reader` declares `read(CharArray, Int, Int)` as its sole
    // virtual member — slot 0 in every subclass vtable (BufferedReader /
    // InputStreamReader / StringReader / user subclasses).
    static let readerReadChars = 0

    static let inputRead = 1
    static let inputAvailable = 2
    static let inputSkip = 3
    static let inputReadList = 4
    static let inputReadByteArray = 5
    static let inputReadRange = 6
    static let inputReadAllBytes = 7
    static let inputMark = 8
    static let inputReset = 9
    static let inputMarkSupported = 10
    static let inputClose = 11

    static let outputWriteByte = 1
    static let outputWriteList = 2
    static let outputWriteByteArray = 3
    static let outputWriteRange = 4
    static let outputFlush = 5
    static let outputClose = 6

    // Writer declares only write/flush/close (in that order) — unlike the
    // stream classes it has no synthetic toString member, so its slots start
    // at 0. BufferedWriter inherits these same slots via the override mapping.
    static let writerWrite = 0
    static let writerFlush = 1
    static let writerClose = 2
}

/// Registers the reader-box nominal type and ancestry the same way
/// `runtimeRegisterJavaWriter`/`runtimeRegisterIoStream` do for their
/// producers: without the nominal typeID and `typeParents` edges, `is`/`as`
/// checks (`kk_op_is`) on raw `RuntimeBufferedReaderBox` handles answered
/// `false` for `java.io.Reader`, `java.io.BufferedReader`/`InputStreamReader`
/// and every closeable interface (KUU-3860).
func runtimeRegisterJavaReader(_ objectRaw: Int, fqName: String, parentFQName: String) {
    let nominalID = runtimeStableNominalTypeID(fqName: fqName)
    runtimeRegisterObjectType(rawValue: objectRaw, classID: nominalID)
    let parentID = runtimeStableNominalTypeID(fqName: parentFQName)
    let closeNames = ["kotlin.io.Closeable", "java.io.Closeable", "kotlin.AutoCloseable", "java.lang.AutoCloseable"]
    runtimeStorage.withMetadataLock { state in
        if nominalID != parentID { state.typeParents[nominalID, default: []].insert(parentID) }
        for name in closeNames { state.typeParents[parentID, default: []].insert(runtimeStableNominalTypeID(fqName: name)) }
    }
    let closeEntry = unsafeBitCast(ioBufferedReaderCloseEntry, to: Int.self)
    let closeableInterfaces = [
        "kotlin.AutoCloseable",
        "kotlin.io.Closeable",
        "java.io.Closeable",
        "java.lang.AutoCloseable",
    ]
    for (interfaceSlot, interfaceName) in closeableInterfaces.enumerated() {
        _ = kk_object_register_itable_iface(
            objectRaw,
            Int(runtimeStableNominalTypeID(fqName: interfaceName)),
            interfaceSlot
        )
        _ = kk_object_register_itable_method(objectRaw, interfaceSlot, 0, closeEntry)
    }
    // Install `Reader.read(CharArray, Int, Int)` (vtable slot
    // `readerReadChars`) so `reader.read(buf, off, len)` on a Reader-typed
    // receiver reaches the box through the same entry Kotlin subclasses
    // dispatch (KUU-4031).
    _ = kk_object_register_vtable_method(
        objectRaw,
        RuntimeIoStreamVTableSlot.readerReadChars,
        unsafeBitCast(ioReaderReadRangeEntry, to: Int.self)
    )
}

func runtimeRegisterJavaWriter(
    _ object: any RuntimeJavaWriter,
    fqName: String,
    parentFQName: String
) -> Int {
    let raw = registerRuntimeObject(object, typeID: runtimeStableNominalTypeID(fqName: fqName))
    let parentID = runtimeStableNominalTypeID(fqName: parentFQName)
    let nominalID = runtimeStableNominalTypeID(fqName: fqName)
    let closeNames = ["kotlin.io.Closeable", "java.io.Closeable", "kotlin.AutoCloseable", "java.lang.AutoCloseable"]
    runtimeStorage.withMetadataLock { state in
        state.typeParents[nominalID, default: []].insert(parentID)
        for name in closeNames { state.typeParents[parentID, default: []].insert(runtimeStableNominalTypeID(fqName: name)) }
    }
    let closeEntry = unsafeBitCast(ioWriterCloseEntry, to: Int.self)
    let closeableInterfaces = [
        "kotlin.AutoCloseable",
        "kotlin.io.Closeable",
        "java.io.Closeable",
        "java.lang.AutoCloseable",
    ]
    for (interfaceSlot, interfaceName) in closeableInterfaces.enumerated() {
        _ = kk_object_register_itable_iface(raw, Int(runtimeStableNominalTypeID(fqName: interfaceName)), interfaceSlot)
        _ = kk_object_register_itable_method(raw, interfaceSlot, 0, closeEntry)
    }
    // Fixed vtable bridge slots matching the synthetic java.io.Writer layout:
    // base-typed calls (w: Writer; w.flush()) dispatch through these so a
    // Kotlin subclass override wins while the box resolves to the same
    // __kk_buffered_writer_* bridge a direct call would have used (KUU-3860).
    let writerVtableEntries: [(slot: Int, entry: Int)] = [
        (RuntimeIoStreamVTableSlot.writerWrite, unsafeBitCast(ioWriterWriteEntry, to: Int.self)),
        (RuntimeIoStreamVTableSlot.writerFlush, unsafeBitCast(ioWriterFlushEntry, to: Int.self)),
        (RuntimeIoStreamVTableSlot.writerClose, unsafeBitCast(ioWriterCloseEntry, to: Int.self)),
    ]
    for registration in writerVtableEntries {
        _ = kk_object_register_vtable_method(raw, registration.slot, registration.entry)
    }
    if object is RuntimeStringWriterBox {
        _ = kk_object_register_any_to_string(
            raw,
            unsafeBitCast(ioStringWriterToStringEntry, to: Int.self)
        )
    }
    return raw
}

/// Register each runtime stream allocation's nominal type, interface entries,
/// and fixed vtable bridge slots. The box still has no generated class fields
/// or KTypeInfo descriptor.
func runtimeRegisterIoStream(_ object: AnyObject, fqName: String, input: Bool) -> Int {
    let raw = registerRuntimeObject(object, typeID: runtimeStableNominalTypeID(fqName: fqName))
    let baseName = input ? "java.io.InputStream" : "java.io.OutputStream"
    let baseID = runtimeStableNominalTypeID(fqName: baseName)
    let nominalID = runtimeStableNominalTypeID(fqName: fqName)
    let closeNames = ["kotlin.io.Closeable", "java.io.Closeable", "kotlin.AutoCloseable", "java.lang.AutoCloseable"]
    runtimeStorage.withMetadataLock { state in
        if nominalID != baseID { state.typeParents[nominalID, default: []].insert(baseID) }
        for name in closeNames { state.typeParents[baseID, default: []].insert(runtimeStableNominalTypeID(fqName: name)) }
    }
    let entry = input ? unsafeBitCast(ioInputCloseEntry, to: Int.self) : unsafeBitCast(ioOutputCloseEntry, to: Int.self)
    _ = kk_object_register_itable_method(raw, 0, 0, entry)
    for name in closeNames {
        _ = kk_object_register_itable_iface(raw, Int(runtimeStableNominalTypeID(fqName: name)), 0)
    }
    let vtableEntries: [(slot: Int, entry: Int)] = if input {
        [
            (RuntimeIoStreamVTableSlot.inputRead, unsafeBitCast(ioInputReadEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputAvailable, unsafeBitCast(ioInputAvailableEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputSkip, unsafeBitCast(ioInputSkipEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputReadList, unsafeBitCast(ioInputReadBytesEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputReadByteArray, unsafeBitCast(ioInputReadBytesEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputReadRange, unsafeBitCast(ioInputReadRangeEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputReadAllBytes, unsafeBitCast(ioInputReadAllBytesEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputMark, unsafeBitCast(ioInputMarkEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputReset, unsafeBitCast(ioInputResetEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputMarkSupported, unsafeBitCast(ioInputMarkSupportedEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.inputClose, unsafeBitCast(ioInputCloseEntry, to: Int.self)),
        ]
    } else {
        [
            (RuntimeIoStreamVTableSlot.outputWriteByte, unsafeBitCast(ioOutputWriteByteEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.outputWriteList, unsafeBitCast(ioOutputWriteBytesEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.outputWriteByteArray, unsafeBitCast(ioOutputWriteBytesEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.outputWriteRange, unsafeBitCast(ioOutputWriteRangeEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.outputFlush, unsafeBitCast(ioOutputFlushEntry, to: Int.self)),
            (RuntimeIoStreamVTableSlot.outputClose, unsafeBitCast(ioOutputCloseEntry, to: Int.self)),
        ]
    }
    for registration in vtableEntries {
        _ = kk_object_register_vtable_method(raw, registration.slot, registration.entry)
    }
    if object is RuntimeKotlinInputStreamBox || (object as? RuntimeOutputStreamBox)?.hasKotlinDescription == true {
        _ = kk_object_register_any_to_string(raw, unsafeBitCast(ioDescriptionEntry, to: Int.self))
    }
    return raw
}
