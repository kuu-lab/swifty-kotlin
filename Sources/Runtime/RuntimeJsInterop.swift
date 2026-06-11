
// MARK: - kotlin.js JsReference (STDLIB-JS-FN-004)

final class RuntimeJsReferenceBox {
    let valueRaw: Int

    init(valueRaw: Int) {
        self.valueRaw = valueRaw
    }
}

private func runtimeJsReferenceBox(from rawValue: Int) -> RuntimeJsReferenceBox? {
    resolveRuntimeHandle(rawValue, as: RuntimeJsReferenceBox.self)
}

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
