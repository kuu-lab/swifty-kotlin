import Foundation

extension JVMPreparationPhase {
    /// Every platform implementation is a real Kotlin source, selected in
    /// stable resource order. ABI-only declarations live in a separate tree.
    func injectJVMStdlibSources(_ ctx: CompilationContext) throws {
        let base = try JVMStdlibCatalog.resourceRoot()
        let directory = base.appendingPathComponent("jvm/kotlin")
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { throw JVMFrontendError(message: "Missing JVM stdlib implementation directory.") }
        let platform = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "kt" }.sorted { $0.path < $1.path }
        guard !platform.isEmpty else { throw JVMFrontendError(message: "Empty JVM stdlib implementation profile.") }
        let common = try JVMStdlibCatalog.manifest().commonSources.map { base.appendingPathComponent($0) }
        for url in common + platform {
            let source = try Data(contentsOf: url)
            _ = ctx.sourceManager.addFile(path: url.path, contents: source, origin: .user)
        }
    }
}
