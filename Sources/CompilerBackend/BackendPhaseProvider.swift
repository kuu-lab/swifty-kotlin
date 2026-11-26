import CompilerCore
import Foundation

public func makeBackendPhases() -> [CompilerPhase] {
    makeBackendPhases(keepLLVMContextAlive: false)
}

public func makeBackendPhases(keepLLVMContextAlive: Bool) -> [CompilerPhase] {
    // The frontend compiles Android Java sources before Sema and needs the
    // runtime jar the backend builds for `-include-runtime`.
    AndroidBuildInputs.runtimeJarProvider = { try JVMCodegenPhase.runtimeJar(for: $0) }
    let session = LLVMBackendSession(keepContextAlive: keepLLVMContextAlive)
    return [CodegenPhase(session: session), LinkPhase(session: session)]
}

public func prefetchBackendLinkInputs(for options: CompilerOptions) {
    guard options.emit == .executable, !options.target.isWasm else { return }
    RuntimeLinkInputPrefetch.shared.start(target: options.target, configuration: .release)
}

final class RuntimeLinkInputPrefetch: @unchecked Sendable {
    typealias Inputs = (objects: [String], linkerCacheDirectory: URL, fingerprint: String)

    static let shared = RuntimeLinkInputPrefetch()

    private struct Slot {
        let target: TargetTriple
        let configuration: RuntimeBuildConfiguration
        var result: Inputs?
        var finished = false
    }

    private let condition = NSCondition()
    private var slot: Slot?

    func start(target: TargetTriple, configuration: RuntimeBuildConfiguration) {
        condition.lock()
        slot = Slot(target: target, configuration: configuration)
        condition.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var result: Inputs?
            if let cacheKey = try? CodegenRuntimeSupport.runtimeBuildCacheKey(target: target, configuration: configuration) {
                let manifestURL = CodegenRuntimeSupport.runtimeSharedScratchRoot()
                    .appendingPathComponent(cacheKey, isDirectory: true)
                    .appendingPathComponent("objects-\(configuration.rawValue).manifest")
                if !CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(manifestURL: manifestURL).isEmpty {
                    result = try? CodegenRuntimeSupport.runtimeLinkInputs(target: target, configuration: configuration)
                }
            }
            condition.lock()
            if slot?.target == target, slot?.configuration == configuration {
                slot?.result = result
                slot?.finished = true
            }
            condition.broadcast()
            condition.unlock()
        }
    }

    func take(target: TargetTriple, configuration: RuntimeBuildConfiguration) -> Inputs? {
        condition.lock()
        defer { condition.unlock() }
        while let current = slot, current.target == target, current.configuration == configuration {
            if current.finished {
                slot = nil
                guard let result = current.result,
                      result.objects.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
                else { return nil }
                return result
            }
            condition.wait()
        }
        return nil
    }
}

/// Read-only by design — it must never trigger a runtime build.
public func incrementalEnvironmentFingerprint(for options: CompilerOptions) -> [String] {
    guard options.emit == .executable else { return [] }
    var parts: [String] = []
    let configuration = RuntimeBuildConfiguration.release
    do {
        let cacheKey = try CodegenRuntimeSupport.runtimeBuildCacheKey(
            target: options.target, configuration: configuration
        )
        parts.append("runtimeBuildKey=\(cacheKey)")
        let manifestURL = CodegenRuntimeSupport.runtimeSharedScratchRoot()
            .appendingPathComponent(cacheKey, isDirectory: true)
            .appendingPathComponent("objects-\(configuration.rawValue).manifest")
        let objects = CodegenRuntimeSupport.manifestValidatedRuntimeObjectPaths(
            manifestURL: manifestURL
        )
        if objects.isEmpty {
            parts.append("runtimeObjects=absent")
        } else {
            for path in objects.sorted() {
                parts.append("runtimeObject=\(path)|\(MacOSLinkerPlan.signature(path) ?? "missing")")
            }
        }
    } catch {
        parts.append("runtime=unavailable:\(error)")
    }
    let swiftcPath = CommandRunner.resolveExecutable("swiftc", fallback: "/usr/bin/swiftc")
    let linkPlanIdentity = MacOSLinkerPlan.cacheIdentity(
        swiftcPath: swiftcPath,
        driverArguments: LinkPhase().linkerDriverArgs(for: options.target),
        environment: ProcessInfo.processInfo.environment
    )
    parts.append("linkPlan=\(linkPlanIdentity)")
    return parts
}
