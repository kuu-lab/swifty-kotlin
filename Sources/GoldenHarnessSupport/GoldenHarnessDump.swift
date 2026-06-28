@testable import CompilerCore
import Foundation

/// Golden dumps are intended to run in a dedicated worker process.
/// Each dump uses a fresh `CompilationContext` from `makeCompilationContext`.

enum GoldenHarnessDumpError: Error, CustomStringConvertible {
    case missingSourceFile
    case missingSyntaxTree
    case missingAST
    case missingSema

    var description: String {
        switch self {
        case .missingSourceFile: "source file not registered after loading"
        case .missingSyntaxTree: "syntax tree not available after parse"
        case .missingAST: "AST not available after frontend"
        case .missingSema: "sema module not available"
        }
    }
}

enum GoldenHarnessDump {
    static func dumpLexer(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenLexer", emit: .kirDump)
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)

        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }

        var lines: [String] = []
        for token in ctx.tokens where token.range.start.file == sourceFileID {
            lines.append("\(GoldenHarnessSyntaxFormat.renderTokenKind(token.kind, interner: ctx.interner)) \(GoldenHarnessSyntaxFormat.renderRange(token.range))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpParser(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenParser", emit: .kirDump)
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)

        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }
        guard let (_, syntax, root) = ctx.syntaxTrees.first(where: { $0.0 == sourceFileID }) else {
            throw GoldenHarnessDumpError.missingSyntaxTree
        }
        var lines: [String] = []
        GoldenHarnessSyntaxFormat.dumpSyntaxNode(
            id: root,
            syntax: syntax,
            interner: ctx.interner,
            indent: "",
            lines: &lines
        )
        return lines.joined(separator: "\n") + "\n"
    }

    static func dumpSema(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenSema", emit: .kirDump)
        try runFrontend(ctx)
        try SemaPhase().run(ctx)

        guard let ast = ctx.ast else {
            throw GoldenHarnessDumpError.missingAST
        }
        guard let sema = ctx.sema else {
            throw GoldenHarnessDumpError.missingSema
        }
        guard let sourceFileID = ctx.sourceManager.fileID(forPath: sourcePath) else {
            throw GoldenHarnessDumpError.missingSourceFile
        }

        return renderSemaOutput(ast: ast, sema: sema, interner: ctx.interner, sourceFileID: sourceFileID)
    }

    // MARK: - Stable sema rendering

    private static func renderSemaOutput(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceFileID: FileID
    ) -> String {
        let ctx = StableRenderContext(sema: sema, interner: interner)

        // 1. Render body lines (files, decls, exprs) first to track referenced symbols
        var bodyLines: [String] = []

        for file in ast.sortedFiles where file.fileID == sourceFileID {
            bodyLines.append(renderFile(file, ast: ast, ctx: ctx))
        }

        for raw in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(raw))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else { continue }
            let hasType = sema.bindings.exprTypes[exprID] != nil
            let hasRef = sema.bindings.identifierSymbols[exprID] != nil
            let hasCall = sema.bindings.callBindings[exprID] != nil
            guard hasType || hasRef || hasCall else { continue }
            bodyLines.append(renderExpression(expr, id: exprID, ctx: ctx))
        }

        // 2. Transitively expand required symbols
        ctx.expandRequiredSymbols()

        // 3. Render only required symbol lines, sorted by FQ name for stability
        let requiredSymbols = sema.symbols.allSymbols()
            .filter { ctx.requiredSymbols.contains($0.id.rawValue) }
            .sorted { ctx.stableKey(for: $0.id) < ctx.stableKey(for: $1.id) }

        var symbolLines: [String] = []
        for symbol in requiredSymbols {
            symbolLines.append(renderSymbol(symbol, ctx: ctx))
        }

        return (symbolLines + bodyLines).joined(separator: "\n") + "\n"
    }

    private static func renderSymbol(_ symbol: SemanticSymbol, ctx: StableRenderContext) -> String {
        var extra: [String] = []
        if let signature = ctx.sema.symbols.functionSignature(for: symbol.id) {
            extra.append("sig=\(ctx.renderSignature(signature))")
        }
        if let propertyType = ctx.sema.symbols.propertyType(for: symbol.id) {
            extra.append("type=\(ctx.renderType(propertyType))")
        }
        let extras = extra.isEmpty ? "" : " " + extra.joined(separator: " ")
        let key = ctx.stableKey(for: symbol.id)
        let flags = GoldenHarnessSemaFormat.renderSymbolFlags(symbol.flags)
        return "symbol fq=\(key) kind=\(symbol.kind) vis=\(symbol.visibility) flags=\(flags)\(extras)"
    }

    private static func renderFile(_ file: ASTFile, ast: ASTModule, ctx: StableRenderContext) -> String {
        var fileLine = "file f\(file.fileID.rawValue) package=\(GoldenHarnessSemaFormat.renderFQName(file.packageFQName, interner: ctx.interner))"
        if !file.annotations.isEmpty {
            let renderedAnnotations = file.annotations.map { annotation in
                let targetPrefix = annotation.useSiteTarget.map { "@\($0):" } ?? "@"
                let arguments = if annotation.arguments.isEmpty {
                    ""
                } else {
                    "(\(annotation.arguments.map(GoldenHarnessSemaFormat.renderAnnotationArgument).joined(separator: ",")))"
                }
                return "\(targetPrefix)\(annotation.name)\(arguments)"
            }.joined(separator: ",")
            fileLine += " annotations=[\(renderedAnnotations)]"
        }

        var lines = [fileLine]
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID) else { continue }
            let symKey: String
            if let symbolID = ctx.sema.bindings.declSymbols[declID] {
                ctx.requireSymbol(symbolID)
                symKey = ctx.stableKey(for: symbolID)
            } else {
                symKey = "_"
            }
            lines.append(
                "  decl d\(declID.rawValue) \(GoldenHarnessSemaFormat.renderDecl(decl, interner: ctx.interner)) sym=\(symKey)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func renderExpression(_ expr: Expr, id: ExprID, ctx: StableRenderContext) -> String {
        var line = "expr e\(id.rawValue) \(GoldenHarnessExprFormat.renderExpr(expr, interner: ctx.interner))"

        if let exprType = ctx.sema.bindings.exprTypes[id] {
            line += " type=\(ctx.renderType(exprType))"
        } else {
            line += " type=_"
        }

        if let refSymbol = ctx.sema.bindings.identifierSymbols[id] {
            if refSymbol.rawValue >= 0 {
                ctx.requireSymbol(refSymbol)
                line += " ref=\(ctx.stableKey(for: refSymbol))"
            } else {
                line += " ref=s\(refSymbol.rawValue)"
            }
        }

        if let callBinding = ctx.sema.bindings.callBindings[id] {
            ctx.requireSymbol(callBinding.chosenCallee)
            line += " call=\(ctx.stableKey(for: callBinding.chosenCallee))"
            if !callBinding.substitutedTypeArguments.isEmpty {
                let typeArgs = callBinding.substitutedTypeArguments.map { ctx.renderType($0) }.joined(separator: ",")
                line += " targs=[\(typeArgs)]"
            }
        }

        return line
    }

    static func dumpDiagnostics(sourcePath: String) throws -> String {
        let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenDiag", emit: .kirDump)
        do {
            try runFrontend(ctx)
            try SemaPhase().run(ctx)
        } catch {
            // Compilation errors are expected for diagnostic test cases.
        }
        let json = ctx.diagnostics.renderJSON(ctx.sourceManager)
        let normalized = json.replacingOccurrences(
            of: sourcePath,
            with: URL(fileURLWithPath: sourcePath).lastPathComponent
        )
        return normalized + "\n"
    }
}
