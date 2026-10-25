import Foundation

private let ioDescriptionEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_io_stream_to_string(raw, thrown)
}

private let ioInputCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_input_stream_close_throwing(raw, thrown)
}
private let ioOutputCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_output_stream_close_throwing(raw, thrown)
}
private let ioBufferedReaderCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return __kk_buffered_reader_close(raw)
}

private let ioWriterCloseEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    __kk_buffered_writer_close_throwing(raw, thrown)
}

private let ioStringWriterToStringEntry: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, thrown in
    thrown?.pointee = 0
    return __kk_string_writer_to_string(raw)
}

func runtimeRegisterBufferedReaderCloseDispatch(_ objectRaw: Int) {
    let closeEntry = unsafeBitCast(ioBufferedReaderCloseEntry, to: Int.self)
    for (interfaceName, interfaceSlot) in [("kotlin.AutoCloseable", 0), ("kotlin.io.Closeable", 1)] {
        _ = kk_object_register_itable_iface(
            objectRaw,
            Int(runtimeStableNominalTypeID(fqName: interfaceName)),
            interfaceSlot
        )
        _ = kk_object_register_itable_method(objectRaw, interfaceSlot, 0, closeEntry)
    }
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
    for (interfaceName, interfaceSlot) in [("kotlin.AutoCloseable", 0), ("kotlin.io.Closeable", 1)] {
        _ = kk_object_register_itable_iface(raw, Int(runtimeStableNominalTypeID(fqName: interfaceName)), interfaceSlot)
        _ = kk_object_register_itable_method(raw, interfaceSlot, 0, closeEntry)
    }
    if object is RuntimeStringWriterBox {
        _ = kk_object_register_any_to_string(
            raw,
            unsafeBitCast(ioStringWriterToStringEntry, to: Int.self)
        )
    }
    return raw
}

/// Register each allocation after metadata resets; this does not invent class
/// fields or a JVM classfile/vtable representation.
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
    if object is RuntimeKotlinInputStreamBox || (object as? RuntimeOutputStreamBox)?.hasKotlinDescription == true {
        _ = kk_object_register_any_to_string(raw, unsafeBitCast(ioDescriptionEntry, to: Int.self))
    }
    return raw
}
