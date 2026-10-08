
import CompilerCore

enum CodegenRuntimeSupport {
    static func targetTripleString(_ target: TargetTriple) -> String {
        if let osVersion = target.osVersion, !osVersion.isEmpty {
            return "\(target.arch)-\(target.vendor)-\(target.os)\(osVersion)"
        }
        return "\(target.arch)-\(target.vendor)-\(target.os)"
    }

    static func stableFNV1a64Hex(_ value: String) -> String {
        // Generated identifiers and runtime lock/file names retain their historical minimal-width format.
        StableFNV1a64.hex(value, zeroPadded: false)
    }
}
