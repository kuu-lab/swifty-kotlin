import Foundation

protocol CompilerPlugin: Sendable {
    var id: String { get }

    /// Sema-phase transform, run after declaration annotations have been
    /// canonicalized to FQ names and before validation passes consume
    /// symbol flags (modality, overrides, inheritance checks).
    func applySemaTransform(_ context: CompilerPluginSemaContext)

    /// Sema-phase transform, run after `bindInheritanceEdges` has populated
    /// `directSupertypes`/`supertypeTypeArgs` and the bundled-supertype
    /// patches have settled, but before override/sealed/delegation
    /// validation. Plugins that must inspect a declaration's resolved
    /// supertypes (e.g. no-arg's superclass constructor check) implement
    /// this hook instead of `applySemaTransform`.
    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext)

    var loweringPasses: [any LoweringPass] { get }
}

extension CompilerPlugin {
    func applySemaTransform(_ context: CompilerPluginSemaContext) {}
    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {}
    var loweringPasses: [any LoweringPass] { [] }
}

struct CompilerPluginSemaContext {
    let ast: ASTModule
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let diagnostics: DiagnosticEngine
    let interner: StringInterner
    let options: CompilerOptions
    let pluginConfig: CompilerPluginConfig
    let sema: SemaModule
}

struct CompilerPluginConfig {
    private(set) var values: [String: [String: [String]]] = [:]

    static func parse(frontendFlags: [String]) -> CompilerPluginConfig {
        var config = CompilerPluginConfig()
        for flag in frontendFlags where flag.hasPrefix("plugin:") {
            let rest = flag.dropFirst("plugin:".count)
            guard let idEnd = rest.firstIndex(of: ":") else { continue }
            let id = String(rest[..<idEnd])
            let optionPart = rest[rest.index(after: idEnd)...]
            guard let eq = optionPart.firstIndex(of: "=") else { continue }
            let key = String(optionPart[..<eq])
            let value = String(optionPart[optionPart.index(after: eq)...])
            config.values[id, default: [:]][key, default: []].append(value)
        }
        return config
    }

    func optionValues(for pluginID: String, key: String) -> [String] {
        values[pluginID]?[key] ?? []
    }
}

enum CompilerPluginRegistry {
    static let builtins: [any CompilerPlugin] = [
        AllOpenPlugin(),
        NoArgPlugin(),
        ParcelizePlugin(),
        KotlinxSerializationPlugin(),
        SamWithReceiverPlugin(),
        AssignmentPlugin(),
        PowerAssertPlugin(),
        LombokPlugin(),
        ComposePlugin(),
    ]

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var dynamicPluginsCache: [String: [any CompilerPlugin]] = [:]

    static func plugins(for options: CompilerOptions) -> [any CompilerPlugin] {
        let pluginFlags = options.frontendFlags.filter { $0.hasPrefix("-Xplugin=") || $0.hasPrefix("plugin:") }
        guard !pluginFlags.isEmpty else {
            return builtins
        }
        let cacheKey = pluginFlags.joined(separator: "\n")
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = dynamicPluginsCache[cacheKey] {
            return cached
        }

        var result = builtins
        for flag in options.frontendFlags where flag.hasPrefix("-Xplugin=") {
            let jarPath = String(flag.dropFirst("-Xplugin=".count))
            if let descriptor = try? JvmPluginHostClient.shared.inspectPlugin(pluginJarPath: jarPath) {
                result.append(JvmCompilerPlugin(jarPath: jarPath, descriptor: descriptor))
            }
        }
        dynamicPluginsCache[cacheKey] = result
        return result
    }

    static func clearDynamicPluginsCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        dynamicPluginsCache.removeAll()
    }

    static func semaContext(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        options: CompilerOptions,
        sema: SemaModule
    ) -> CompilerPluginSemaContext {
        CompilerPluginSemaContext(
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics,
            interner: interner,
            options: options,
            pluginConfig: CompilerPluginConfig.parse(frontendFlags: options.frontendFlags),
            sema: sema
        )
    }
}

extension DataFlowSemaPhase {
    /// Runs every built-in plugin's Sema transform. Invoked after
    /// `canonicalizeDeclarationAnnotations` so trigger annotations are
    /// already resolved to canonical FQ names, and before inheritance /
    /// override validation so flag changes take effect.
    func runCompilerPluginTransforms(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        sema: SemaModule,
        ctx: CompilationContext
    ) {
        let pluginCtx = CompilerPluginRegistry.semaContext(
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            options: ctx.options,
            sema: sema
        )
        for plugin in CompilerPluginRegistry.plugins(for: ctx.options) {
            plugin.applySemaTransform(pluginCtx)
        }
    }

    /// Runs every active plugin's post-inheritance Sema transform.
    /// Invoked after `bindInheritanceEdges` and the bundled-supertype
    /// patches so `directSupertypes`/`supertypeTypeArgs` are populated,
    /// and before override/sealed/delegation validation.
    func runCompilerPluginPostInheritanceTransforms(
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        bindings: BindingTable,
        sema: SemaModule,
        ctx: CompilationContext
    ) {
        let pluginCtx = CompilerPluginRegistry.semaContext(
            ast: ast,
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            options: ctx.options,
            sema: sema
        )
        for plugin in CompilerPluginRegistry.plugins(for: ctx.options) {
            plugin.applyPostInheritanceSemaTransform(pluginCtx)
        }
    }
}
