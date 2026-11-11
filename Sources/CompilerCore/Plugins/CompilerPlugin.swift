import Foundation

/// Built-in compiler plugin support — the KSwiftK equivalent of kotlinc's
/// `-Xplugin` mechanism. Plugins are compiled into the compiler and run at
/// fixed pipeline hook points. Configuration uses the kotlinc-compatible
/// `plugin:<pluginID>:<option>=<value>` convention, supplied through `-P`
/// CLI arguments (stored as frontend flags) or `-Xfrontend`.
///
/// This is the built-in half of the plugin story: the protocol and hook
/// points are deliberately phase-oriented so a future dynamic plugin
/// loader can adapt external binaries onto the same surface without
/// changing call sites.
protocol CompilerPlugin: Sendable {
    /// Stable plugin identifier, e.g. `org.jetbrains.kotlin.allopen`.
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

    /// Lowering passes contributed by this plugin. They run before the
    /// standard pipeline so generated KIR flows through every built-in
    /// desugaring/ABI pass.
    var loweringPasses: [any LoweringPass] { get }
}

extension CompilerPlugin {
    func applySemaTransform(_ context: CompilerPluginSemaContext) {}
    func applyPostInheritanceSemaTransform(_ context: CompilerPluginSemaContext) {}
    var loweringPasses: [any LoweringPass] { [] }
}

/// Everything a Sema-phase plugin transform may inspect or mutate.
struct CompilerPluginSemaContext {
    let ast: ASTModule
    let symbols: SymbolTable
    let types: TypeSystem
    let bindings: BindingTable
    let diagnostics: DiagnosticEngine
    let interner: StringInterner
    let options: CompilerOptions
    let pluginConfig: CompilerPluginConfig
    /// The owning sema module. Plugins that synthesize declarations record
    /// them here (e.g. `sema.pluginGeneratedConstructors`) so later phases
    /// can recognize plugin-generated symbols.
    let sema: SemaModule
}

/// Parsed `plugin:<id>:<key>=<value>` frontend flags. Repeatable options
/// accumulate values in declaration order.
struct CompilerPluginConfig {
    /// pluginID -> option name -> values
    private(set) var values: [String: [String: [String]]] = [:]

    static func parse(frontendFlags: [String]) -> CompilerPluginConfig {
        var config = CompilerPluginConfig()
        for flag in frontendFlags where flag.hasPrefix("plugin:") {
            // plugin:<id>:<key>=<value>; the value may itself contain '='.
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

    var isEmpty: Bool { values.isEmpty }

    func optionValues(for pluginID: String, key: String) -> [String] {
        values[pluginID]?[key] ?? []
    }
}

/// Registry of compiler plugins compiled into the compiler.
enum CompilerPluginRegistry {
    /// Built-in plugins in execution order. Each plugin self-gates on its
    /// configuration and on whether its trigger annotations are present.
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

    /// Resolves all active plugins for the compilation: built-in plugins plus
    /// any dynamic JVM plugins supplied via `-Xplugin=<path.jar>`.
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
        // Every plugin self-gates: configured plugins check their options,
        // fixed-trigger plugins check whether their annotation resolved.
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
