import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CompilerCore

enum CodegenCriticalSection {
    /// Process-local lock used during codegen on Linux. Object emission touches
    /// LLVM global target state, so concurrent codegen calls within one process
    /// are serialized here. Cross-process serialization is unnecessary because
    /// each `kswiftc` process has its own LLVM context and output path.
    static func withLinuxExecutableCodegenProcessLock<T>(
        target: TargetTriple,
        body: () throws -> T
    ) rethrows -> T {
        guard target.os.hasPrefix("linux") else {
            return try body()
        }

        linuxCodegenProcessLock.lock()
        defer { linuxCodegenProcessLock.unlock() }
        return try body()
    }

    private static let linuxCodegenProcessLock = NSLock()
}
