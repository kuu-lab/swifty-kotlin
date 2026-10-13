import Foundation
import RuntimeABI

/// Compiler startup bridge. argv is borrowed only while copying its strings.
/// This is not a public Kotlin process-arguments API.
@_cdecl("__kk_process_args_from_argv")
public func __kk_process_args_from_argv(_ argc: Int32, _ argvRaw: UnsafeRawPointer?) -> Int {
    let count = argc > 1 && argvRaw != nil ? Int(argc) - 1 : 0
    let box = RuntimeArrayBox(length: count)
    if let argvRaw, count > 0 {
        let argv = argvRaw.assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
        for index in 0..<count {
            // Valid OS argv has no interior nil entries. Use an empty string
            // defensively for a nil slot without creating a null String value.
            let text = argv[index + 1].map { String(decodingCString: $0, as: UTF8.self) } ?? ""
            box[index] = registerRuntimeObject(RuntimeStringBox(KotlinStringSurrogateEncoding.encode(text)))
        }
    }
    let raw = registerRuntimeObject(box)
    runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
    return raw
}
