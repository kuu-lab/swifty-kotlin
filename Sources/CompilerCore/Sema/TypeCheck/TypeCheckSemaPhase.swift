
/// Semantic analysis pass that performs type checking and type inference.
///
/// This phase is a thin wrapper around ``TypeCheckDriver``, which dispatches
/// type-checking work to independent delegate classes (`ExprTypeChecker`,
/// `CallTypeChecker`, `ControlFlowTypeChecker`, etc.). Each delegate holds only
/// the context it needs, replacing the previous extension-based splitting
/// where a single monolithic class shared all state across multiple files.
final class TypeCheckSemaPhase: CompilerPhase {
    static let name = "TypeCheckSema"

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard let sema = ctx.sema else {
            throw CompilerPipelineError.invalidInput("Semantic model is unavailable.")
        }

        guard let ast = ctx.ast else {
            throw CompilerPipelineError.invalidInput("AST is unavailable during type check.")
        }

        let semaCacheEnabled = ctx.options.frontendFlags.contains("sema-cache")
        let semaCacheContext: SemaCacheContext? = semaCacheEnabled ? SemaCacheContext() : nil

        let solver = ConstraintSolver()
        let resolver = OverloadResolver()
        if let semaCacheContext {
            resolver.cacheContext = semaCacheContext
        }
        let dataFlow = DataFlowAnalyzer()
        let semaCtx = SemaModule(
            symbols: sema.symbols,
            types: sema.types,
            bindings: sema.bindings,
            diagnostics: ctx.diagnostics
        )

        let lazyBoundDecls = collectLazyBoundObjectLiteralDecls(ast: ast)

        // Run consistency checks for active declarations only, so incremental
        // frontends can drop stale declarations from the previous compile.
        let activeDeclIDs = ast.activeDeclarationIDs
        for declID in activeDeclIDs {
            if lazyBoundDecls.contains(declID) {
                continue
            }
            if sema.bindings.declSymbols[declID] == nil {
                ctx.diagnostics.error(
                    "KSWIFTK-TYPE-0003",
                    "Unbound declaration found during type checking.",
                    range: nil
                )
            }
        }

        let driver = TypeCheckDriver(
            ast: ast,
            sema: sema,
            semaCtx: semaCtx,
            solver: solver,
            resolver: resolver,
            dataFlow: dataFlow,
            interner: ctx.interner,
            diagnostics: ctx.diagnostics,
            semaCacheContext: semaCacheContext,
            useNewInference: ctx.options.useNewInference,
            useUnrestrictedBuilderInference: ctx.options.useUnrestrictedBuilderInference,
            useProperTypeInferenceConstraintsProcessing: ctx.options.useProperTypeInferenceConstraintsProcessing,
            globalOptInMarkerNames: ctx.options.optInMarkerNames
        )

        let fileScopes = driver.scopeBuilder.buildFileScopes(
            ast: ast,
            sema: sema,
            interner: ctx.interner
        )

        // Expression type inference recurses with large per-frame contexts
        // (`TypeInferenceContext` is threaded by value through every call).
        // Swift Testing executes tests as tasks on the Swift Concurrency
        // cooperative pool, whose threads have 512 KiB stacks, so type-checking
        // even moderately nested call/lambda chains there can overflow and
        // crash with SIGBUS (signal 10). Run it on a big-stack thread so
        // recursion headroom is independent of the calling thread, matching
        // `BuildKIRPhase`'s handling of the same class of issue in lowering.
        let work = TypeCheckWork(driver: driver, fileScopes: fileScopes, files: ast.files)
        try LargeStackExecutor.run {
            work.run()
        }

        for declID in lazyBoundDecls where activeDeclIDs.contains(declID) && sema.bindings.declSymbols[declID] == nil {
            let declRange: SourceRange? = if let decl = ast.arena.decl(declID) {
                switch decl {
                case let .classDecl(classDecl):
                    classDecl.range
                case let .interfaceDecl(interfaceDecl):
                    interfaceDecl.range
                case let .funDecl(funDecl):
                    funDecl.range
                case let .propertyDecl(propertyDecl):
                    propertyDecl.range
                case let .typeAliasDecl(typeAliasDecl):
                    typeAliasDecl.range
                case let .objectDecl(objectDecl):
                    objectDecl.range
                case let .enumEntryDecl(enumEntryDecl):
                    enumEntryDecl.range
                }
            } else {
                nil
            }
            ctx.diagnostics.error(
                "KSWIFTK-TYPE-0003",
                "Unbound declaration found during type checking.",
                range: declRange
            )
        }
    }

    private func collectLazyBoundObjectLiteralDecls(ast: ASTModule) -> Set<DeclID> {
        var declsToSkip: Set<DeclID> = []
        for expr in ast.arena.exprs {
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID
            else {
                continue
            }
            collectObjectLiteralDeclTree(declID, ast: ast, into: &declsToSkip)
        }
        return declsToSkip
    }

    private func collectObjectLiteralDeclTree(
        _ declID: DeclID,
        ast: ASTModule,
        into declsToSkip: inout Set<DeclID>
    ) {
        guard declsToSkip.insert(declID).inserted,
              let decl = ast.arena.decl(declID)
        else {
            return
        }
        guard case let .objectDecl(objectDecl) = decl else {
            return
        }
        for childDeclID in objectDecl.memberFunctions
            + objectDecl.memberProperties
            + objectDecl.nestedClasses
            + objectDecl.nestedObjects
        {
            collectObjectLiteralDeclTree(childDeclID, ast: ast, into: &declsToSkip)
        }
    }
}

/// Holds the non-`Sendable` type-checking inputs and exposes a `@Sendable`
/// callable surface so the large-stack thread can run `typeCheckModule`
/// without capturing non-`Sendable` values through `withoutActuallyEscaping`
/// closures.
private final class TypeCheckWork: @unchecked Sendable {
    let driver: TypeCheckDriver
    let fileScopes: [Int32: FileScope]
    let files: [ASTFile]

    init(driver: TypeCheckDriver, fileScopes: [Int32: FileScope], files: [ASTFile]) {
        self.driver = driver
        self.fileScopes = fileScopes
        self.files = files
    }

    func run() {
        driver.typeCheckModule(fileScopes: fileScopes, files: files)
    }
}
