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
        let commonSource: Bool?
        let runtimeFacade: String?
        let onlyForStdlibBuild: Bool?
        let appendForConsumers: String?
        let consumerIdentifiers: Set<String>?
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
    static func read(_ path: String, commonSource: Bool = false) throws -> Data {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw JVMFrontendError(message: "Invalid JVM stdlib resource path.") }
        return try Data(contentsOf: resourceRoot().appendingPathComponent(commonSource ? path : "jvm/" + path))
    }

    package static func runtimeSourceFingerprint() throws -> String {
        let root = try resourceRoot()
        let jvm = root.appendingPathComponent("jvm")
        guard let files = FileManager.default.enumerator(at: jvm, includingPropertiesForKeys: nil) else {
            throw JVMFrontendError(message: "Missing JVM stdlib resources.")
        }
        let sources = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "kt" }
        var parts = [FileFingerprint.sha256Hex(try Data(contentsOf: jvm.appendingPathComponent("manifest.json")))]
        let rootDepth = root.pathComponents.count
        for source in sources.sorted(by: { $0.path < $1.path }) {
            parts.append(source.pathComponents.dropFirst(rootDepth).joined(separator: "/"))
            parts.append(FileFingerprint.sha256Hex(try Data(contentsOf: source)))
        }
        let catalog = try manifest()
        let common = Set(catalog.commonSources + catalog.declarations.filter { $0.commonSource == true }.map(\.path))
        for path in common.sorted() {
            parts.append(path)
            parts.append(FileFingerprint.sha256Hex(try read(path, commonSource: true)))
        }
        return ContentAddressedStore.makeKey(parts: parts)
    }

    /// Classpath imports must not redeclare types whose source contracts are
    /// already selected. Nested binary names are filtered by the class reader.
    static func nominalNames(in ctx: CompilationContext) throws -> Set<String> {
        let package = try NSRegularExpression(pattern: #"(?m)^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)"#)
        let nominal = try NSRegularExpression(pattern: #"(?m)^\s*(?:(?:public|private|internal|protected|open|abstract|sealed|data|enum|annotation|value|fun)\s+)*(?:class|interface|object|typealias)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
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
        let declarations = try manifest().declarations
        let optionalIdentifiers = Set(declarations.flatMap { $0.consumerIdentifiers ?? [] })
        let referencedIdentifiers = ctx.options.stdlibOnly ? [] : sourceReferences(to: optionalIdentifiers, in: ctx)
        for declaration in declarations {
            if ctx.options.stdlibOnly && declaration.excludeFromStdlibBuild { continue }
            if !ctx.options.stdlibOnly && declaration.onlyForStdlibBuild == true { continue }
            if !ctx.options.stdlibOnly, Self.isKotlinPathDeclaration(declaration.path),
               !userSourcesUseKotlinPath(in: ctx) {
                continue
            }
            if let identifiers = declaration.consumerIdentifiers,
               !ctx.options.stdlibOnly, identifiers.isDisjoint(with: referencedIdentifiers) { continue }
            var source = try read(declaration.path, commonSource: declaration.commonSource == true)
            if !ctx.options.stdlibOnly, let extra = declaration.appendForConsumers {
                let content = String(decoding: try read(extra), as: UTF8.self)
                source.append(Data(content.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n").utf8))
            }
            guard !ctx.sourceManager.containsFile(path: declaration.virtualPath) else { throw JVMFrontendError(message: "Duplicate JVM stdlib declaration injection.") }
            let file = ctx.sourceManager.addFile(path: declaration.virtualPath, contents: source, origin: .residualStdlib)
            ctx.jvmStdlibDeclarationFiles.insert(file)
        }
    }

    private static func userSourcesUseKotlinPath(in ctx: CompilationContext) -> Bool {
        for file in ctx.sourceManager.fileIDs()
        where ctx.sourceManager.origin(of: file) == .user
            && !ctx.sourceManager.path(of: file).hasPrefix("<kswiftk-jvm>/")
        {
            let source = String(decoding: ctx.sourceManager.contents(of: file), as: UTF8.self)
            if JVMJDKClasspath.usesKotlinPath(in: source) { return true }
        }
        return false
    }

    private static func isKotlinPathDeclaration(_ path: String) -> Bool {
        path.hasPrefix("kotlin/io/path/")
            || path == "declarations/KotlinIoPath.kt"
            || path == "declarations/PathPredicates.kt"
    }

    // Optional adapters can refer to platform classes whose signatures pull
    // more dependencies into the lazy importer. Load those contracts on use.
    private static func sourceReferences(to identifiers: Set<String>, in ctx: CompilationContext) -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        var referenced: Set<String> = []
        for file in ctx.sourceManager.fileIDs() where ctx.sourceManager.origin(of: file) == .user {
            let contents = ctx.sourceManager.contents(of: file)
            let text = String(decoding: contents, as: UTF8.self)
            guard identifiers.contains(where: { text.contains($0) }) else { continue }
            let interner = StringInterner()
            let lexer = KotlinLexer(file: file, source: contents, interner: interner, diagnostics: DiagnosticEngine())
            for token in lexer.lexAll() {
                switch token.kind {
                case let .identifier(name), let .backtickedIdentifier(name):
                    let name = interner.resolve(name)
                    if identifiers.contains(name) { referenced.insert(name) }
                default:
                    break
                }
            }
            if referenced == identifiers { break }
        }
        return referenced
    }
}
