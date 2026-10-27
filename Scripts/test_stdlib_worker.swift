import CompilerBackend
import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct TestStdlibWorker {
    static func watchParent() -> Bool {
        let parent = getppid()
        guard parent > 1 else { return false }
        Thread.detachNewThread {
            while getppid() == parent {
                Thread.sleep(forTimeInterval: 1)
            }
            _exit(1)
        }
        return true
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--parent-watch-test"] {
            guard watchParent() else { exit(1) }
            FileHandle.standardOutput.write(Data("ready\n".utf8))
            while true { Thread.sleep(forTimeInterval: 60) }
        }
        guard let identity = TestStdlibCompilerIdentity.current() else { exit(2) }
        if arguments == ["--identity"] {
            print(identity)
            return
        }
        guard arguments.count == 3, arguments[0] == "--build", arguments[2] == identity else { exit(2) }
        guard watchParent() else { exit(1) }
        let stageLock = (arguments[1] + ".lock").withCString { open($0, O_RDWR | O_NOFOLLOW) }
        guard stageLock >= 0, flock(stageLock, LOCK_SH) == 0 else { exit(1) }
        defer {
            _ = flock(stageLock, LOCK_UN)
            close(stageLock)
        }
        do {
            let path = try StdlibArtifactBuilder.build(outputBase: arguments[1], target: TargetTriple.hostDefault())
            guard TestStdlibCompilerIdentity.current() == identity else { exit(2) }
            print(path)
        } catch {
            FileHandle.standardError.write(Data("test stdlib worker: \(error)\n".utf8))
            exit(1)
        }
    }
}
