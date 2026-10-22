import CompilerCore
import Foundation

public func makeBackendPhases() -> [CompilerPhase] {
    let session = LLVMBackendSession()
    return [CodegenPhase(session: session), LinkPhase(session: session)]
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
