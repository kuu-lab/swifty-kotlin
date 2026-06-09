
// MARK: - kotlin.js JsReference (STDLIB-JS-FN-004)

final class RuntimeJsReferenceBox {
    let valueRaw: Int

    init(valueRaw: Int) {
        self.valueRaw = valueRaw
    }
}

final class RuntimeJsStringBox {
    let value: String

    init(value: String) {
        self.value = value
    }
}

private func runtimeJsReferenceBox(from rawValue: Int) -> RuntimeJsReferenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeJsReferenceBox.self)
}

// MARK: - kotlin.js String.toJsString

@_cdecl("kk_string_toJsString_flat")
public func kk_string_toJsString_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let value = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return registerRuntimeObject(RuntimeJsStringBox(value: value))
}

// MARK: - kotlin.js JsReference (STDLIB-JS-FN-004)

@_cdecl("kk_js_reference_get")
public func kk_js_reference_get(_ jsRefRaw: Int) -> Int {
    guard let reference = runtimeJsReferenceBox(from: jsRefRaw) else {
        fatalError(
            "KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_js_reference_get received invalid JsReference handle"
        )
    }
    return reference.valueRaw
}

// MARK: - kotlin.js.collections JsReadonlySet conversions (STDLIB-JS-COLLECTIONS-FN-005)

@_cdecl("kk_js_set_toMutableSet")
public func kk_js_set_toMutableSet(_ jsSetRaw: Int) -> Int {
    guard let set = runtimeSetBox(from: jsSetRaw) else {
        return registerRuntimeObject(RuntimeSetBox(elements: []))
    }
    return registerRuntimeObject(RuntimeSetBox(elements: Array(set.elements)))
}
