import Foundation

/// The manifest is shared by source injection, library generation and auditing.
/// Declaration-only contracts are deliberately separate from compiled bodies.
package enum JVMStdlibCatalog {
    struct Manifest: Decodable {
        let schemaVersion: Int
        let commonSources: [String]
        let runtimeClassAliases: [String: String]?
        let declarations: [Declaration]
    }
    struct Declaration: Decodable {
        let path: String
        let virtualPath: String
        let excludeFromStdlibBuild: Bool
        let runtimeFacade: String?
        let onlyForStdlibBuild: Bool?
        let appendForConsumers: String?
    }
    static func resourceRoot() throws -> URL {
        guard let resources = Bundle.module.resourcePath else { throw JVMFrontendError(message: "Missing JVM stdlib resources.") }
        return URL(fileURLWithPath: resources).appendingPathComponent("Stdlib")
    }
    static func manifest() throws -> Manifest {
        let root = try resourceRoot().appendingPathComponent("jvm")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        guard manifest.schemaVersion == 1 else { throw JVMFrontendError(message: "Unsupported JVM stdlib source manifest version.") }
        let paths = manifest.declarations.map(\.virtualPath)
        guard paths.count == Set(paths).count else { throw JVMFrontendError(message: "Duplicate JVM stdlib declaration path.") }
        return manifest
    }
    static func read(_ path: String) throws -> Data {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw JVMFrontendError(message: "Invalid JVM stdlib resource path.") }
        return try Data(contentsOf: resourceRoot().appendingPathComponent("jvm/" + path))
    }
    /// Classpath imports must not redeclare types whose source contracts are
    /// already selected. Nested binary names are filtered by the class reader.
    static func nominalNames(in ctx: CompilationContext) throws -> Set<String> {
        let package = try NSRegularExpression(pattern: #"(?m)^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)"#)
        let nominal = try NSRegularExpression(pattern: #"(?m)^\s*(?:(?:public|private|internal|protected|open|abstract|sealed|data|enum|annotation|value|fun)\s+)*(?:class|interface|object)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        var names: Set<String> = []
        for file in ctx.sourceManager.fileIDs() where ctx.sourceManager.path(of: file).hasPrefix("<kswiftk-jvm>/") || ctx.options.stdlibOnly && ctx.sourceManager.origin(of: file) == .user {
            let source = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self) as NSString
            let range = NSRange(location: 0, length: source.length)
            guard let match = package.firstMatch(in: source as String, range: range) else { continue }
            let prefix = source.substring(with: match.range(at: 1)).replacingOccurrences(of: ".", with: "/")
            for match in nominal.matches(in: source as String, range: range) { names.insert(prefix + "/" + source.substring(with: match.range(at: 1))) }
        }
        return names
    }
    static func injectDeclarations(into ctx: CompilationContext) throws {
        for declaration in try manifest().declarations {
            if ctx.options.stdlibOnly && declaration.excludeFromStdlibBuild { continue }
            if !ctx.options.stdlibOnly && declaration.onlyForStdlibBuild == true { continue }
            var source = try read(declaration.path)
            if !ctx.options.stdlibOnly, let extra = declaration.appendForConsumers {
                let content = String(decoding: try read(extra), as: UTF8.self)
                source.append(Data(content.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n").utf8))
            }
            guard !ctx.sourceManager.containsFile(path: declaration.virtualPath) else { throw JVMFrontendError(message: "Duplicate JVM stdlib declaration injection.") }
            _ = ctx.sourceManager.addFile(path: declaration.virtualPath, contents: source, origin: .residualStdlib)
        }
    }
}
