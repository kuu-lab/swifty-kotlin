import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CompilerCore

enum CodegenCriticalSection {
    /// Process-local lock for LLVM target initialization and native emission on
    /// Linux. LLVM's target registry is process-global and is not safe to touch
    /// concurrently, even when each compilation owns a separate context and
    /// output path. Cross-process serialization is unnecessary because each
    /// `kswiftc` process has its own LLVM target registry.
    static func withLinuxLLVMProcessLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) rethrows -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        linuxLLVMProcessLock.lock()
        defer { linuxLLVMProcessLock.unlock() }
        return try body()
    }

    private static let linuxLLVMProcessLock = NSLock()
}
