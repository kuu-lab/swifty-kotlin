import CompilerCore
import Foundation

public func makeBackendPhases() -> [CompilerPhase] {
    makeBackendPhases(keepLLVMContextAlive: false)
}

public func makeBackendPhases(keepLLVMContextAlive: Bool) -> [CompilerPhase] {
    let session = LLVMBackendSession(keepContextAlive: keepLLVMContextAlive)
    return [CodegenPhase(session: session), LinkPhase(session: session)]
}

/// Starts resolving the runtime link inputs on a background thread so they
/// are ready (or in flight) by the time Link needs them. Only fires when the
/// verified manifest already exists, so it can never start a runtime build for
/// a compilation that may still fail. The result is single-use and consumed by
/// `LinkPhase`, which falls back to a normal resolve on any miss or error.
public func prefetchBackendLinkInputs(for options: CompilerOptions) {
    guard options.emit == .executable, !options.target.isWasm else { return }
    RuntimeLinkInputPrefetch.shared.start(target: options.target, configuration: .release)
}

final class RuntimeLinkInputPrefetch: @unchecked Sendable {
    typealias Inputs = (objects: [String], linkerCacheDirectory: URL)

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

    /// Waits for an in-flight prefetch and consumes its result; nil when none
    /// was started for this target/configuration or it did not produce inputs.
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

/// Link-affecting inputs only the backend can see, folded into the
/// incremental build-configuration hash for executable emission: the
/// packaged runtime objects (their cache key binds the Runtime sources, so
/// a rebuilt runtime invalidates cached executables) and the linker plan
/// identity (toolchain resolution, Xcode selection, driver arguments).
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
            // Manifest absent or objects missing: the link would rebuild them,
            // and the rebuilt tree gets a different signature anyway.
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
