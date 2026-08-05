#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CharSyntheticMemberLinkTests {

    private func externalLink(
        for member: String,
        parameterCount: Int = 0,
        sema: SemaModule,
        interner: StringInterner,
        receiverType: TypeID? = nil
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        let targetReceiverType = receiverType ?? sema.types.charType
        let sym = sema.symbols.lookupAll(fqName: fq).first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == targetReceiverType
                && signature.parameterTypes.count == parameterCount
        } ?? sema.symbols.lookup(fqName: fq)
        guard let sym else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }
    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testCharPredicateStubsHaveCorrectExternalLinks
            """
            package sample0
            fun noop() {}
            """,
            // testIntDigitToCharStubsHaveCorrectExternalLinks
            """
            package sample1
            fun noop() {}
            """,
            // testKotlinTextPackageIsParentedUnderKotlinPackage
            """
            package sample2
            fun noop() {}
            """,
            // testCharCategoryEnumSurfaceIsRegistered
            """
            package sample3
            fun noop() {}
            """,
            // testCharCategoryPropertyReturnsCharCategoryEnum
            """
            package sample4
            fun noop() {}
            """,
            // testCharDirectionalityReturnsEnumType
            """
            package sample5
            fun noop() {}
            """,
            // testNativeCharCompanionHelpersAreRegistered
            """
            package sample6
            fun noop() {}
            """,
            // testCharLocaleCaseStubHasCorrectExternalLink
            """
            package sample7
            fun noop() {}
            """,
            // testCharDigitToIntOrNullRadixStubHasCorrectExternalLink
            """
            package sample8
            fun noop() {}
            """,
            // testCharDigitToIntOrNullRadixResolvesInCallExpressions
            """
            package sample9

                    fun probe(ch: Char) { ch.digitToIntOrNull(16) }

            """,
            // testCharPredicateMembersResolveInCallExpressions
            """
            package sample10

                    fun probe(ch: Char) {
                        ch.isDigit()
                        ch.isLetter()
                        ch.isLetterOrDigit()
                        ch.isWhitespace()
                        ch.isDefined()
                        ch.isIdentifierIgnorable()
                        ch.digitToInt()
                        ch.digitToIntOrNull()
                        ch.uppercase()
                        ch.uppercaseChar()
                        ch.lowercase()
                        ch.lowercaseChar()
                        ch.titlecase()
                        ch.titlecaseChar()
                        // New numeric conversion functions
                        ch.toInt()
                        ch.toDouble()
                        ch.toIntOrNull()
                        ch.toDoubleOrNull()
                        // Code point and Unicode properties
                        ch.code
                        ch.category
                        ch.directionality
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCharPredicateStubsHaveCorrectExternalLinks ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // KSP-661: isDigit/isLetter/isLetterOrDigit/isWhitespace/isDefined は
                // bundled Kotlin へ移行済みのため合成スタブの外部リンクを持たない。
                let expected: [String: String] = [
                    "isIdentifierIgnorable": "kk_char_isIdentifierIgnorable",
                    "digitToInt": "kk_char_digitToInt",
                    "digitToIntOrNull": "kk_char_digitToIntOrNull",
                    "uppercaseChar": "kk_char_uppercaseChar",
                    "lowercaseChar": "kk_char_lowercaseChar",
                    "titlecaseChar": "kk_char_titlecaseChar",
                    // New numeric conversion functions
                    "toInt": "kk_char_toInt",
                    "toDouble": "kk_char_toDouble",
                    "toIntOrNull": "kk_char_toIntOrNull",
                    "toDoubleOrNull": "kk_char_toDoubleOrNull",
                    // Code point and Unicode properties
                    "code": "kk_char_code",
                    "category": "kk_char_category",
                    "directionality": "kk_char_directionality",
                ]

                for (member, expectedLink) in expected {
                    #expect(externalLink(for: member, sema: sema, interner: interner) == expectedLink, "Char.\(member) should link to \(expectedLink)")
                }

            }

            // === testIntDigitToCharStubsHaveCorrectExternalLinks ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let expected: [(parameterCount: Int, expectedLink: String)] = [
                    (parameterCount: 0, expectedLink: "kk_char_digitToChar_radix"),
                    (parameterCount: 1, expectedLink: "kk_char_digitToChar_radix"),
                ]

                for item in expected {
                    #expect(externalLink(
                            for: "digitToChar",
                            parameterCount: item.parameterCount,
                            sema: sema,
                            interner: interner,
                            receiverType: sema.types.intType
                        ) == item.expectedLink, "Int.digitToChar overload with \(item.parameterCount) parameter(s) should link to \(item.expectedLink)")
                }

            }

            // === testKotlinTextPackageIsParentedUnderKotlinPackage ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let kotlinSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin")]))
                let kotlinTextSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("text")]))

                #expect(sema.symbols.parentSymbol(for: kotlinTextSymbol) == kotlinSymbol)

            }

            // === testCharCategoryEnumSurfaceIsRegistered ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let charCategorySymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("CharCategory"),
                ]))
                #expect(sema.symbols.symbol(charCategorySymbol)?.kind == .enumClass)

                let charCategoryType = sema.types.make(.classType(ClassType(
                    classSymbol: charCategorySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let entries = [
                    "UNASSIGNED",
                    "UPPERCASE_LETTER",
                    "LOWERCASE_LETTER",
                    "TITLECASE_LETTER",
                    "MODIFIER_LETTER",
                    "OTHER_LETTER",
                    "NON_SPACING_MARK",
                    "ENCLOSING_MARK",
                    "COMBINING_SPACING_MARK",
                    "DECIMAL_DIGIT_NUMBER",
                    "LETTER_NUMBER",
                    "OTHER_NUMBER",
                    "SPACE_SEPARATOR",
                    "LINE_SEPARATOR",
                    "PARAGRAPH_SEPARATOR",
                    "CONTROL",
                    "FORMAT",
                    "PRIVATE_USE",
                    "SURROGATE",
                    "DASH_PUNCTUATION",
                    "START_PUNCTUATION",
                    "END_PUNCTUATION",
                    "CONNECTOR_PUNCTUATION",
                    "OTHER_PUNCTUATION",
                    "MATH_SYMBOL",
                    "CURRENCY_SYMBOL",
                    "MODIFIER_SYMBOL",
                    "OTHER_SYMBOL",
                    "INITIAL_QUOTE_PUNCTUATION",
                    "FINAL_QUOTE_PUNCTUATION",
                ]

                for entry in entries {
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: [
                        interner.intern("kotlin"),
                        interner.intern("text"),
                        interner.intern("CharCategory"),
                        interner.intern(entry),
                    ]), "CharCategory.\(entry) must be registered")
                    #expect(sema.symbols.propertyType(for: entrySymbol) == charCategoryType)
                }

            }

            // === testCharCategoryPropertyReturnsCharCategoryEnum ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let charCategorySymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("CharCategory"),
                ]))
                let categoryFunction = try #require(sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("category"),
                ]).first { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
                })
                let signature = try #require(sema.symbols.functionSignature(for: categoryFunction))
                guard case let .classType(categoryClassType) = sema.types.kind(of: signature.returnType) else {
                    Issue.record("Char.category should return kotlin.text.CharCategory"); return
                }
                #expect(categoryClassType.classSymbol == charCategorySymbol)

            }

            // === testCharDirectionalityReturnsEnumType ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let enumFQName = ["kotlin", "text", "CharDirectionality"].map { interner.intern($0) }
                let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
                let enumType = sema.types.make(.classType(ClassType(
                    classSymbol: enumSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let directionalityFQName = ["kotlin", "text", "directionality"].map { interner.intern($0) }
                let directionalitySymbol = try #require(sema.symbols.lookupAll(fqName: directionalityFQName).first { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.receiverType == sema.types.charType
                })
                #expect(sema.symbols.functionSignature(for: directionalitySymbol)?.returnType == enumType)

                for entry in ["UNDEFINED", "LEFT_TO_RIGHT", "RIGHT_TO_LEFT_ARABIC", "COMMON_NUMBER_SEPARATOR", "WHITESPACE"] {
                    let entrySymbol = try #require(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
                    #expect(sema.symbols.propertyType(for: entrySymbol) == enumType)
                }

            }

            // === testNativeCharCompanionHelpersAreRegistered ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let charSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("Char"),
                ]))
                let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: charSymbol))
                let companionInfo = try #require(sema.symbols.symbol(companionSymbol))
                let charArraySymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("CharArray"),
                ]))
                let charArrayType = sema.types.make(.classType(ClassType(
                    classSymbol: charArraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let expected: [(name: String, link: String, params: [TypeID], returnType: TypeID)] = [
                    (
                        name: "isSupplementaryCodePoint",
                        link: "kk_char_isSupplementaryCodePoint",
                        params: [sema.types.intType],
                        returnType: sema.types.booleanType
                    ),
                    (
                        name: "isSurrogatePair",
                        link: "kk_char_isSurrogatePair",
                        params: [sema.types.charType, sema.types.charType],
                        returnType: sema.types.booleanType
                    ),
                    (
                        name: "toChars",
                        link: "kk_char_toChars",
                        params: [sema.types.intType],
                        returnType: charArrayType
                    ),
                    (
                        name: "toCodePoint",
                        link: "kk_char_toCodePoint",
                        params: [sema.types.charType, sema.types.charType],
                        returnType: sema.types.intType
                    ),
                ]

                for item in expected {
                    let functionSymbol = try #require(sema.symbols.lookupAll(fqName: companionInfo.fqName + [
                        interner.intern(item.name),
                    ]).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.parameterTypes == item.params
                            && signature.returnType == item.returnType
                    })
                    #expect(sema.symbols.parentSymbol(for: functionSymbol) == companionSymbol)
                    #expect(sema.symbols.externalLinkName(for: functionSymbol) == item.link)
                    #expect(sema.symbols.annotations(for: functionSymbol).contains {
                            $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi"
                        }, "Char.Companion.\(item.name) should require ExperimentalNativeApi")
                }

            }

            // === testCharLocaleCaseStubHasCorrectExternalLink ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(externalLink(for: "lowercase", parameterCount: 1, sema: sema, interner: interner) == "kk_char_lowercase_locale")
                #expect(externalLink(for: "uppercase", parameterCount: 1, sema: sema, interner: interner) == "kk_char_uppercase_locale")

            }

            // === testCharDigitToIntOrNullRadixStubHasCorrectExternalLink ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(externalLink(for: "digitToIntOrNull", parameterCount: 1, sema: sema, interner: interner) == "kk_char_digitToIntOrNull_radix")

            }

            // === testCharDigitToIntOrNullRadixResolvesInCallExpressions ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                #expect(!(sample9Diagnostics.contains { $0.severity == .error }))

            }

            // === testCharPredicateMembersResolveInCallExpressions ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let expectedFunctionLinks: [String: String] = [
                    "isIdentifierIgnorable": "kk_char_isIdentifierIgnorable",
                    "digitToInt": "kk_char_digitToInt",
                    "digitToIntOrNull": "kk_char_digitToIntOrNull",
                    "uppercaseChar": "kk_char_uppercaseChar",
                    "lowercaseChar": "kk_char_lowercaseChar",
                    "uppercase": "kk_char_uppercase",
                    "lowercase": "kk_char_lowercase",
                    "titlecase": "kk_char_titlecase",
                    "titlecaseChar": "kk_char_titlecaseChar",
                    "toInt": "kk_char_toInt",
                    "toDouble": "kk_char_toDouble",
                    "toIntOrNull": "kk_char_toIntOrNull",
                    "toDoubleOrNull": "kk_char_toDoubleOrNull",
                ]
                let expectedPropertyLinks: [String: String] = [
                    "code": "kk_char_code",
                    "category": "kk_char_category",
                    "directionality": "kk_char_directionality",
                ]

                for (memberName, externalLinkName) in expectedFunctionLinks {
                    let callExpr = try #require(firstExprIDInPath(in: ast, path: sample10Path, ctx: ctx) { exprID, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr,
                              interner.resolve(callee) == memberName,
                              let range = ast.arena.exprRange(exprID)
                        else { return false }
                        return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                    }, "Expected member call to \(memberName) in AST")
                    #expect(sema.bindings.exprTypes[callExpr] != sema.types.errorType)
                    if let chosenCallee = sema.bindings.callBinding(for: callExpr)?.chosenCallee
                        ?? sema.bindings.identifierSymbol(for: callExpr)
                    {
                        #expect(sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                    }
                }

                for (memberName, externalLinkName) in expectedPropertyLinks {
                    let propertyExpr = try #require(firstExprIDInPath(in: ast, path: sample10Path, ctx: ctx) { exprID, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == memberName,
                              args.isEmpty,
                              let range = ast.arena.exprRange(exprID)
                        else { return false }
                        return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                    }, "Expected property access to \(memberName) in AST")
                    #expect(sema.bindings.exprTypes[propertyExpr] != sema.types.errorType)
                    if let chosenSymbol = sema.bindings.identifierSymbol(for: propertyExpr) {
                        #expect(sema.symbols.externalLinkName(for: chosenSymbol) == externalLinkName, "Expected \(memberName) to resolve to \(externalLinkName)")
                    }
                }

            }

        }
    }

}

#endif
