import Foundation
import RuntimeABI

@_cdecl("__kk_process_args_from_argv")
public func __kk_process_args_from_argv(_ argc: Int32, _ argvRaw: UnsafeRawPointer?) -> Int {
    let count = argc > 1 && argvRaw != nil ? Int(argc) - 1 : 0
    let box = RuntimeArrayBox(length: count)
    box.installComponentTypeIfAbsent(__kk_array_component_type(2, 0))
    if let argvRaw, count > 0 {
        let argv = argvRaw.assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
        for index in 0..<count {
            let text = argv[index + 1].map { String(decodingCString: $0, as: UTF8.self) } ?? ""
            box[index] = registerRuntimeObject(RuntimeStringBox(KotlinStringSurrogateEncoding.encode(text)))
        }
    }
    let raw = registerRuntimeObject(box)
    runtimeRegisterArrayType(rawValue: raw, typeID: runtimeStableNominalTypeID(fqName: "kotlin.Array"))
    return raw
}
