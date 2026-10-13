// SDK dispatch / memory representation / GC ownership only; public IO logic is Kotlin.
public extension RuntimeABISpec {
    static let appleFoundationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(name: "__kk_foundation_attach", parameters: [
            RuntimeABIParameter(name: "owner", type: .intptr),
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_object_create", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_object_kind", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_object_equals", parameters: [
            RuntimeABIParameter(name: "lhs", type: .intptr),
            RuntimeABIParameter(name: "rhs", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation", returnsRawBoolean: true),
        RuntimeABIFunctionSpec(name: "__kk_foundation_object_hash", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_data_create", parameters: [
            RuntimeABIParameter(name: "bytes", type: .intptr),
            RuntimeABIParameter(name: "length", type: .intptr),
            RuntimeABIParameter(name: "noCopy", type: .intptr),
            RuntimeABIParameter(name: "freeWhenDone", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_data_base64", parameters: [
            RuntimeABIParameter(name: "text", type: .intptr),
            RuntimeABIParameter(name: "options", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_data_length", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_data_bytes", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_error_create", parameters: [
            RuntimeABIParameter(name: "domain", type: .intptr),
            RuntimeABIParameter(name: "code", type: .intptr),
            RuntimeABIParameter(name: "description", type: .intptr),
            RuntimeABIParameter(name: "underlying", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_error_description", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_url_file", parameters: [
            RuntimeABIParameter(name: "path", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_input_create", parameters: [
            RuntimeABIParameter(name: "data", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_input_url", parameters: [
            RuntimeABIParameter(name: "url", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_output_create", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_stream_call", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "operation", type: .intptr),
            RuntimeABIParameter(name: "arg1", type: .intptr),
            RuntimeABIParameter(name: "arg2", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_stream_install", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "block", type: .intptr),
            RuntimeABIParameter(name: "input", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_stream_delegate", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "block", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_stream_event", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "event", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_current", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_perform", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "modes", type: .intptr),
            RuntimeABIParameter(name: "block", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_run", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_stop", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_add_port", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "port", type: .intptr),
            RuntimeABIParameter(name: "mode", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_port_create", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_thread_create", parameters: [
            RuntimeABIParameter(name: "block", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_thread_current", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_thread_name", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_thread_set_name", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "name", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_thread_start", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_pinned_bytes_address", parameters: [
            RuntimeABIParameter(name: "pinned", type: .intptr),
            RuntimeABIParameter(name: "index", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_memcpy", parameters: [
            RuntimeABIParameter(name: "dst", type: .intptr),
            RuntimeABIParameter(name: "src", type: .intptr),
            RuntimeABIParameter(name: "length", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_memset", parameters: [
            RuntimeABIParameter(name: "dst", type: .intptr),
            RuntimeABIParameter(name: "value", type: .intptr),
            RuntimeABIParameter(name: "length", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_malloc", parameters: [
            RuntimeABIParameter(name: "length", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_free", parameters: [
            RuntimeABIParameter(name: "pointer", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_errno", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_strerror", parameters: [
            RuntimeABIParameter(name: "code", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_byte_pointer_add", parameters: [
            RuntimeABIParameter(name: "pointer", type: .intptr),
            RuntimeABIParameter(name: "offset", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_lock_create", parameters: [
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_lock_lock", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_lock_unlock", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_access", parameters: [
            RuntimeABIParameter(name: "path", type: .intptr),
            RuntimeABIParameter(name: "mode", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
        RuntimeABIFunctionSpec(name: "__kk_foundation_runloop_cf_pointer", parameters: [
            RuntimeABIParameter(name: "handle", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ], returnType: .intptr, section: "AppleFoundation"),
    ]
}
