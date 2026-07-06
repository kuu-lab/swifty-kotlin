@testable import CompilerCore
import Foundation
import Testing
import XCTest

/// Verifies that the new String stdlib extension stubs added in the PR
/// (STDLIB-006, STDLIB-009) are registered in the symbol table with the
/// correct runtime external link names.
@Suite
struct StringSyntheticMemberLinkTests {
    /// Resolve the `kotlin.text.<member>` symbol and return its external link name.
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(for member: String, sema: SemaModule, interner: StringInterner) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) })
    }

    private func externalLink(
        for member: String,
        receiverType: TypeID,
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookupAll(fqName: fq).first(where: { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes.count == parameterCount
        }) else {
            return nil
        }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func allExprIDs(in ast: ASTModule, where predicate: (ExprID, Expr) -> Bool) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            if predicate(exprID, expr) {
                results.append(exprID)
            }
        }
        return results
    }

    @Test func testExistingStringStubsRetainCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "trim": "kk_string_trim_flat",
            "split": "kk_string_split_flat",
            "startsWith": "kk_string_startsWith_flat",
            "endsWith": "kk_string_endsWith_flat",
            "toInt": "kk_string_toInt",
            "toDouble": "kk_string_toDouble",
            "hexToShort": "kk_string_hexToShort_flat",
            "hexToUByte": "kk_string_hexToUByte_flat",
            "hexToUByteArray": "kk_string_hexToUByteArray_flat",
            "hexToUInt": "kk_string_hexToUInt_flat",
            "hexToULong": "kk_string_hexToULong_flat",
            "hexToUShort": "kk_string_hexToUShort_flat",
        ]

        for (member, expectedLink) in expected {
            let links = externalLinks(for: member, sema: sema, interner: interner)
            #expect(
                links.contains(expectedLink),
                "String.\(member) should link to \(expectedLink), got \(links.sorted())"
            )
        }
        #expect(
            externalLinks(for: "indexOfAny", sema: sema, interner: interner)
                .contains("kk_string_indexOfAny_chars"),
            "CharSequence.indexOfAny(chars, startIndex, ignoreCase) should link to kk_string_indexOfAny_chars"
        )
        #expect(
            externalLinks(for: "indexOfAny", sema: sema, interner: interner)
                .contains("kk_string_indexOfAny_strings"),
            "CharSequence.indexOfAny(strings, startIndex, ignoreCase) should link to kk_string_indexOfAny_strings"
        )
        #expect(
            externalLinks(for: "lastIndexOfAny", sema: sema, interner: interner)
                .contains("kk_string_lastIndexOfAny_chars"),
            "CharSequence.lastIndexOfAny(chars, startIndex, ignoreCase) should link to kk_string_lastIndexOfAny_chars"
        )
        #expect(
            externalLinks(for: "lastIndexOfAny", sema: sema, interner: interner)
                .contains("kk_string_lastIndexOfAny_strings"),
            "CharSequence.lastIndexOfAny(strings, startIndex, ignoreCase) should link to kk_string_lastIndexOfAny_strings"
        )
        #expect(
            externalLink(for: "findAnyOf", sema: sema, interner: interner) == "kk_string_findAnyOf",
            "CharSequence.findAnyOf(strings, startIndex, ignoreCase) should link to kk_string_findAnyOf"
        )
        #expect(
            externalLink(for: "findLastAnyOf", sema: sema, interner: interner) == "kk_string_findLastAnyOf",
            "CharSequence.findLastAnyOf(strings, startIndex, ignoreCase) should link to kk_string_findLastAnyOf"
        )
        #expect(
            externalLinks(for: "replaceAfter", sema: sema, interner: interner)
                .contains("kk_string_replaceAfter_flat"),
            "String.replaceAfter(String, replacement, missingDelimiterValue) should link to kk_string_replaceAfter_flat"
        )
        #expect(
            externalLinks(for: "replaceAfter", sema: sema, interner: interner)
                .contains("kk_string_replaceAfter_char_flat"),
            "String.replaceAfter(Char, replacement, missingDelimiterValue) should link to kk_string_replaceAfter_char_flat"
        )
        #expect(
            externalLinks(for: "replaceAfterLast", sema: sema, interner: interner)
                .contains("kk_string_replaceAfterLast_flat"),
            "String.replaceAfterLast(String, replacement, missingDelimiterValue) should link to kk_string_replaceAfterLast_flat"
        )
        #expect(
            externalLinks(for: "replaceAfterLast", sema: sema, interner: interner)
                .contains("kk_string_replaceAfterLast_char_flat"),
            "String.replaceAfterLast(Char, replacement, missingDelimiterValue) should link to kk_string_replaceAfterLast_char_flat"
        )
        #expect(
            externalLinks(for: "replaceBefore", sema: sema, interner: interner)
                .contains("kk_string_replaceBefore_flat"),
            "String.replaceBefore(String, replacement, missingDelimiterValue) should link to kk_string_replaceBefore_flat"
        )
        #expect(
            externalLinks(for: "replaceBefore", sema: sema, interner: interner)
                .contains("kk_string_replaceBefore_char_flat"),
            "String.replaceBefore(Char, replacement, missingDelimiterValue) should link to kk_string_replaceBefore_char_flat"
        )
        #expect(
            externalLinks(for: "replaceBeforeLast", sema: sema, interner: interner)
                .contains("kk_string_replaceBeforeLast_flat"),
            "String.replaceBeforeLast(String, replacement, missingDelimiterValue) should link to kk_string_replaceBeforeLast_flat"
        )
        #expect(
            externalLinks(for: "replaceBeforeLast", sema: sema, interner: interner)
                .contains("kk_string_replaceBeforeLast_char_flat"),
            "String.replaceBeforeLast(Char, replacement, missingDelimiterValue) should link to kk_string_replaceBeforeLast_char_flat"
        )
        // STDLIB-TEXT-FN-043: plus overloads (String and String? receiver)
        #expect(
            externalLinks(for: "plus", sema: sema, interner: interner)
                .contains("kk_string_plus"),
            "String?.plus(other: Any?) should link to kk_string_plus"
        )
        // KSP-303: replace overloads are now bundled Kotlin source, not public runtime stubs.
        let replaceLinks = externalLinks(for: "replace", sema: sema, interner: interner)
        #expect(
            !replaceLinks.contains("kk_string_replace_flat")
                && !replaceLinks.contains("kk_string_replace_char_flat")
                && !replaceLinks.contains("kk_string_replace_ignoreCase_flat")
                && !replaceLinks.contains("kk_string_replace_char_ignoreCase_flat")
                && !replaceLinks.contains("kk_string_replace_regex"),
            "String.replace overloads should be source-backed; got \(replaceLinks.sorted())"
        )
    }

    @Test func testNewCaseConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // lowercase() and uppercase() are now bundled Kotlin functions (MIGRATION-TEXT-005) — no C external link.
        // The `externalLink(for:)` helper returns the first match in the symbol table; since
        // Char.lowercase / Char.uppercase share the same FQN prefix, we verify via the String-receiver
        // overloads specifically.
        let lowercaseLinks = externalLinks(for: "lowercase", sema: sema, interner: interner)
        #expect(
            !lowercaseLinks.contains("kk_string_lowercase"),
            "String.lowercase should be a bundled Kotlin function with no C external link (MIGRATION-TEXT-005)"
        )
        let uppercaseLinks = externalLinks(for: "uppercase", sema: sema, interner: interner)
        #expect(
            !uppercaseLinks.contains("kk_string_uppercase"),
            "String.uppercase should be a bundled Kotlin function with no C external link (MIGRATION-TEXT-005)"
        )
        // capitalize() is now a bundled Kotlin function (MIGRATION-TEXT-005) — no C external link.
        #expect(
            externalLink(for: "capitalize", sema: sema, interner: interner) == nil,
            "String.capitalize should be a bundled Kotlin function with no C external link"
        )

        #expect(
            externalLink(for: "__kk_lowercase_locale", sema: sema, interner: interner) == "kk_string_lowercase_locale",
            "String.lowercase(Locale) wrapper should call the private locale primitive"
        )
        #expect(
            externalLink(for: "__kk_uppercase_locale", sema: sema, interner: interner) == "kk_string_uppercase_locale",
            "String.uppercase(Locale) wrapper should call the private locale primitive"
        )
    }

    @Test func testCodePointCountStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let codePointCountLinks = externalLinks(for: "codePointCount", sema: sema, interner: interner)
        #expect(
            codePointCountLinks.contains("kk_string_codePointCount"),
            "CharSequence.codePointCount() should link to kk_string_codePointCount"
        )
        #expect(
            codePointCountLinks.contains("kk_string_codePointCount_from"),
            "CharSequence.codePointCount(startIndex) should link to kk_string_codePointCount_from"
        )
        #expect(
            codePointCountLinks.contains("kk_string_codePointCount_range"),
            "CharSequence.codePointCount(startIndex, endIndex) should link to kk_string_codePointCount_range"
        )
    }

    @Test func testStringNormalizationStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        #expect(
            externalLink(for: "normalize", sema: sema, interner: interner) == "kk_string_normalize_flat",
            "String.normalize should link to kk_string_normalize_flat"
        )
        #expect(
            externalLink(for: "isNormalized", sema: sema, interner: interner) == "kk_string_isNormalized_flat",
            "String.isNormalized should link to kk_string_isNormalized_flat"
        )
    }

    @Test func testChunkedSequenceStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "chunkedSequence", sema: sema, interner: interner)
        #expect(
            links.contains("kk_string_chunked_sequence_transform"),
            "CharSequence.chunkedSequence(size, transform) should link to kk_string_chunked_sequence_transform"
        )
        #expect(
            links.contains("kk_string_chunked_sequence"),
            "CharSequence.chunkedSequence should link to kk_string_chunked_sequence"
        )
    }

    @Test func testNewNullableConversionStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        #expect(
            externalLink(
                for: "toIntOrNull",
                receiverType: sema.types.stringType,
                parameterCount: 0,
                sema: sema,
                interner: interner
            ) == "kk_string_toIntOrNull_flat",
            "String.toIntOrNull should link to kk_string_toIntOrNull_flat"
        )
        #expect(
            externalLinks(for: "toIntOrNull", sema: sema, interner: interner)
                .contains("kk_string_toIntOrNull_radix_flat"),
            "String.toIntOrNull(radix) should link to kk_string_toIntOrNull_radix_flat"
        )
        #expect(
            externalLink(for: "toUByteOrNull", sema: sema, interner: interner) == "kk_string_toUByteOrNull",
            "String.toUByteOrNull should link to kk_string_toUByteOrNull"
        )
        #expect(
            externalLinks(for: "toUByteOrNull", sema: sema, interner: interner)
                .contains("kk_string_toUByteOrNull_radix"),
            "String.toUByteOrNull(radix) should link to kk_string_toUByteOrNull_radix"
        )
        #expect(
            externalLink(for: "toUShortOrNull", sema: sema, interner: interner) == "kk_string_toUShortOrNull",
            "String.toUShortOrNull should link to kk_string_toUShortOrNull"
        )
        #expect(
            externalLinks(for: "toUShortOrNull", sema: sema, interner: interner)
                .contains("kk_string_toUShortOrNull_radix"),
            "String.toUShortOrNull(radix) should link to kk_string_toUShortOrNull_radix"
        )
        #expect(
            externalLink(for: "toUIntOrNull", sema: sema, interner: interner) == "kk_string_toUIntOrNull",
            "String.toUIntOrNull should link to kk_string_toUIntOrNull"
        )
        #expect(
            externalLinks(for: "toUIntOrNull", sema: sema, interner: interner)
                .contains("kk_string_toUIntOrNull_radix"),
            "String.toUIntOrNull(radix) should link to kk_string_toUIntOrNull_radix"
        )
        #expect(
            externalLink(for: "toULongOrNull", sema: sema, interner: interner) == "kk_string_toULongOrNull",
            "String.toULongOrNull should link to kk_string_toULongOrNull"
        )
        #expect(
            externalLinks(for: "toULongOrNull", sema: sema, interner: interner)
                .contains("kk_string_toULongOrNull_radix"),
            "String.toULongOrNull(radix) should link to kk_string_toULongOrNull_radix"
        )
        #expect(
            externalLink(
                for: "toDoubleOrNull",
                receiverType: sema.types.stringType,
                parameterCount: 0,
                sema: sema,
                interner: interner
            ) == "kk_string_toDoubleOrNull",
            "String.toDoubleOrNull should link to kk_string_toDoubleOrNull"
        )
        #expect(
            externalLink(for: "toBigDecimal", sema: sema, interner: interner) == "kk_string_toBigDecimal",
            "String.toBigDecimal should link to kk_string_toBigDecimal"
        )
        #expect(
            externalLink(for: "toBigDecimalOrNull", sema: sema, interner: interner) == "kk_string_toBigDecimalOrNull",
            "String.toBigDecimalOrNull should link to kk_string_toBigDecimalOrNull"
        )
        #expect(
            externalLink(for: "toBigInteger", sema: sema, interner: interner) == "kk_string_toBigInteger",
            "String.toBigInteger should link to kk_string_toBigInteger"
        )
        #expect(
            externalLink(for: "toBigIntegerOrNull", sema: sema, interner: interner) == "kk_string_toBigIntegerOrNull",
            "String.toBigIntegerOrNull should link to kk_string_toBigIntegerOrNull"
        )
    }

    @Test func testNewSubstringAndSearchStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "indexOf": "kk_string_indexOf",
            "lastIndexOf": "kk_string_lastIndexOf",
        ]
        for (member, expectedLink) in expected {
            #expect(
                externalLink(for: member, sema: sema, interner: interner) == expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    @Test func testNewTransformStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // repeat and reversed are now bundled Kotlin functions — no C external link.
        let bundledMembers = ["repeat", "reversed"]
        for member in bundledMembers {
            let fq = ["kotlin", "text", member].map { interner.intern($0) }
            #expect(
                !sema.symbols.lookupAll(fqName: fq).isEmpty,
                "String.\(member) should be registered as a bundled Kotlin symbol"
            )
            #expect(
                externalLink(for: member, sema: sema, interner: interner) == nil,
                "String.\(member) must not have a C external link after migration to Kotlin source"
            )
        }

        let expected: [String: String] = [
            "toList": "kk_string_toList",
            "toCharArray": "kk_string_toCharArray_flat",
            "toTypedArray": "kk_string_toTypedArray_flat",
        ]
        for (member, expectedLink) in expected {
            #expect(
                externalLink(for: member, sema: sema, interner: interner) == expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    @Test func testNewPaddingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        // padStart and padEnd are now bundled Kotlin functions with a default parameter.
        // They have a single symbol with no C external link.
        for member in ["padStart", "padEnd"] {
            let fq = ["kotlin", "text", member].map { interner.intern($0) }
            let symbols = sema.symbols.lookupAll(fqName: fq)
            #expect(!symbols.isEmpty, "String.\(member) should be registered as a bundled Kotlin symbol")
            let links = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
            #expect(links.isEmpty, "String.\(member) must not have C external links after migration to Kotlin source")
        }
    }

    @Test func testStringCollectionAndSequenceResultStubsUseFlatExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [(member: String, parameterCount: Int, link: String)] = [
            ("toSortedSet", 0, "kk_string_toSortedSet_flat"),
            ("toCollection", 1, "kk_string_toCollection_flat"),
            ("asIterable", 0, "kk_string_asIterable_flat"),
            ("lines", 0, "kk_string_lines_flat"),
            ("lineSequence", 0, "kk_string_lineSequence_flat"),
            ("toByteArray", 0, "kk_string_toByteArray_flat"),
            ("toByteArray", 1, "kk_string_toByteArray_charset_flat"),
            ("toByteArray", 2, "kk_string_encodeToByteArray_range_flat"),
            ("encodeToByteArray", 0, "kk_string_encodeToByteArray_flat"),
            ("encodeToByteArray", 1, "kk_string_encodeToByteArray_charset_flat"),
            ("encodeToByteArray", 2, "kk_string_encodeToByteArray_range_flat"),
            ("chunked", 1, "kk_string_chunked_flat"),
            ("windowed", 1, "kk_string_windowed_default_flat"),
            ("windowed", 2, "kk_string_windowed_flat"),
            ("windowed", 3, "kk_string_windowed_partial_flat"),
            ("zipWithNext", 0, "kk_string_zipWithNext_flat"),
            ("asSequence", 0, "kk_string_asSequence_flat"),
            ("withIndex", 0, "kk_string_withIndex_flat"),
        ]

        for item in expected {
            XCTAssertEqual(
                externalLink(
                    for: item.member,
                    receiverType: sema.types.stringType,
                    parameterCount: item.parameterCount,
                    sema: sema,
                    interner: interner
                ),
                item.link,
                "String.\(item.member)/\(item.parameterCount) should link to \(item.link)"
            )
        }
    }

    @Test func testNewSlicingStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: String] = [
            "drop": "kk_string_drop_flat",
            "take": "kk_string_take_flat",
            "dropLast": "kk_string_dropLast_flat",
            "takeLast": "kk_string_takeLast_flat",
        ]
        for (member, expectedLink) in expected {
            #expect(
                externalLink(for: member, sema: sema, interner: interner) == expectedLink,
                "String.\(member) should link to \(expectedLink)"
            )
        }
    }

    @Test func testIfBlankStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        #expect(
            externalLink(for: "ifBlank", sema: sema, interner: interner) == "kk_string_ifBlank",
            "CharSequence.ifBlank should link to kk_string_ifBlank"
        )
    }

    @Test func testIfEmptyStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        #expect(
            externalLink(for: "ifEmpty", sema: sema, interner: interner) == "kk_string_ifEmpty",
            "CharSequence.ifEmpty should link to kk_string_ifEmpty"
        )
    }

    @Test func testChunkedSequenceStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "chunkedSequence", sema: sema, interner: interner)
        #expect(
            links.contains("kk_string_chunked_sequence"),
            "CharSequence.chunkedSequence should link to kk_string_chunked_sequence, got \(links.sorted())"
        )
        #expect(
            links.contains("kk_string_chunked_sequence_transform"),
            "CharSequence.chunkedSequence(size, transform) should link to kk_string_chunked_sequence_transform"
        )
    }

    @Test func testWindowedSequenceStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let windowedLinks = externalLinks(for: "windowedSequence", sema: sema, interner: interner)
        #expect(
            windowedLinks.contains("kk_string_windowedSequence_partial"),
            "CharSequence.windowedSequence should link to kk_string_windowedSequence_partial, got \(windowedLinks.sorted())"
        )
        #expect(
            windowedLinks.contains("kk_string_windowedSequence_transform"),
            "CharSequence.windowedSequence(size, step, partialWindows, transform) should link to kk_string_windowedSequence_transform"
        )
    }

    @Test func testIfBlankResolvesInCallExpressions() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifBlank { "fallback" }
        }

        fun chooseString(value: String): String {
            return value.ifBlank { "fallback" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "ifBlank"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for ifBlank"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_ifBlank",
                    "Expected ifBlank to resolve to kk_string_ifBlank"
                )
            }
        }
    }

    @Test func testIfEmptyResolvesInCallExpressions() throws {
        let source = """
        fun choose(value: CharSequence): String {
            return value.ifEmpty { "fallback" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "ifEmpty"
            }, "Expected member call to ifEmpty in AST")
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected call binding for ifEmpty"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_ifEmpty",
                "Expected ifEmpty to resolve to kk_string_ifEmpty"
            )
        }
    }

    @Test func testTrimPredicateStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: Set<String>] = [
            "trim": ["kk_string_trim_flat", "kk_string_trim_predicate_flat"],
            "trimStart": ["kk_string_trimStart_flat", "kk_string_trimStart_predicate_flat"],
            "trimEnd": ["kk_string_trimEnd_flat", "kk_string_trimEnd_predicate_flat"],
        ]

        for (member, expectedLinks) in expected {
            #expect(
                externalLinks(for: member, sema: sema, interner: interner).isSuperset(of: expectedLinks),
                "String.\(member) should expose no-arg and predicate overload ABI links"
            )
        }
    }

    @Test func testTrimPredicateMembersResolveInCallExpressions() throws {
        let source = """
        fun trimEdges(s: String): String {
            val a = s.trim { it == 'x' }
            val b = s.trimStart { it == 'x' }
            val c = s.trimEnd { it == 'x' }
            return a + b + c
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedLinks: [String: String] = [
                "trim": "kk_string_trim_predicate_flat",
                "trimStart": "kk_string_trimStart_predicate_flat",
                "trimEnd": "kk_string_trimEnd_predicate_flat",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName,
                    "Expected \(memberName) predicate overload to resolve to \(externalLinkName)"
                )
            }
        }
    }

    @Test func testNewStringMembersResolveInCallExpressions() throws {
        let source = """
        fun process(s: String): String {
            val lower = s.lowercase()
            val upper = s.uppercase()
            val cap = s.capitalize()
            val rep = s.repeat(3)
            val rev = s.reversed()
            val first = s.replaceFirstChar { it.uppercase() }
            return lower + upper + cap + rep + rev + first
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // lowercase, uppercase, capitalize, replaceFirstChar, repeat, reversed are now all
            // bundled Kotlin functions (MIGRATION-TEXT-005) — no C external link.
            // Use allExprIDs and filter by String receiver to avoid picking up internal
            // Char.lowercase/Char.uppercase calls that the bundled implementations use.
            for memberName in ["lowercase", "uppercase", "capitalize", "replaceFirstChar", "repeat", "reversed"] {
                // Find a call that resolves to a callee with String receiver type.
                let callExprs = allExprIDs(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }
                let stringReceiverCallee = callExprs.compactMap { callExpr -> SymbolID? in
                    guard let binding = sema.bindings.callBinding(for: callExpr) else { return nil }
                    let sig = sema.symbols.functionSignature(for: binding.chosenCallee)
                    guard sig?.receiverType == sema.types.stringType else { return nil }
                    return binding.chosenCallee
                }.first
                let chosenCallee = try #require(
                    stringReceiverCallee,
                    "Expected a call to String.\(memberName) in AST"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "Expected String.\(memberName) to be a bundled Kotlin function with no C external link"
                )
            }
        }
    }

    @Test func testStringNormalizationMembersResolveInCallExpressions() throws {
        let source = """
        fun normalizeText(s: String): String {
            val normalized = s.normalize(NormalizationForms.NFC)
            let stable = normalized.isNormalized(NormalizationForms.NFC)
            return if (stable) normalized else s
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let expectedLinks: [String: String] = [
                "normalize": "kk_string_normalize_flat",
                "isNormalized": "kk_string_isNormalized_flat",
            ]

            for (memberName, externalLinkName) in expectedLinks {
                let callExpr = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                }, "Expected member call to \(memberName) in AST")
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for \(memberName)"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == externalLinkName,
                    "Expected \(memberName) to resolve to \(externalLinkName)"
                )
            }
        }
    }

    @Test func testChunkedSequenceResolvesInCallExpressions() throws {
        let source = """
        fun chunks(value: CharSequence): Sequence<String> {
            return value.chunkedSequence(2)
        }

        fun stringChunks(value: String): Sequence<String> {
            return value.chunkedSequence(3)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "chunkedSequence"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for chunkedSequence"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_chunked_sequence",
                    "Expected chunkedSequence to resolve to kk_string_chunked_sequence"
                )
            }
        }
    }

    @Test func testChunkedSequenceTransformResolvesInCallExpressions() throws {
        let source = """
        fun chunks(value: CharSequence): Sequence<String> {
            return value.chunkedSequence(2) { chunk -> "" + chunk + "!" }
        }

        fun stringChunks(value: String): Sequence<String> {
            return value.chunkedSequence(3) { "" + it }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "chunkedSequence"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for chunkedSequence"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_chunked_sequence_transform",
                    "Expected chunkedSequence transform to resolve to kk_string_chunked_sequence_transform"
                )
            }
        }
    }

    @Test func testWindowedSequenceResolvesInCallExpressions() throws {
        let source = """
        fun windows(value: CharSequence): Sequence<String> {
            return value.windowedSequence(3, 2, true)
        }

        fun stringWindows(value: String): Sequence<String> {
            return value.windowedSequence(2, 1, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "windowedSequence"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for windowedSequence"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_windowedSequence_partial",
                    "Expected windowedSequence to resolve to kk_string_windowedSequence_partial"
                )
            }
        }
    }

    @Test func testWindowedSequenceTransformResolvesInCallExpressions() throws {
        let source = """
        fun windows(value: CharSequence): Sequence<Int> {
            return value.windowedSequence(3, 2, true) { it.length }
        }

        fun stringWindows(value: String): Sequence<String> {
            return value.windowedSequence(size = 2, step = 1, partialWindows = false) { window -> "" + window }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "windowedSequence"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for windowedSequence"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_windowedSequence_transform",
                    "Expected windowedSequence transform to resolve to kk_string_windowedSequence_transform"
                )
            }
        }
    }

    @Test func testIndexOfAnyCharsResolvesInCallExpressions() throws {
        let source = """
        fun firstAny(value: CharSequence, chars: CharArray): Int {
            return value.indexOfAny(chars, 1, true)
        }

        fun stringFirstAny(value: String): Int {
            return value.indexOfAny(charArrayOf('x'), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indexOfAny"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for indexOfAny"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_indexOfAny_chars",
                    "Expected indexOfAny(chars, startIndex, ignoreCase) to resolve to kk_string_indexOfAny_chars"
                )
            }
        }
    }

    @Test func testIndexOfAnyStringsResolvesInCallExpressions() throws {
        let source = """
        fun firstAny(value: CharSequence, strings: Collection<String>): Int {
            return value.indexOfAny(strings, 1, true)
        }

        fun stringFirstAny(value: String): Int {
            return value.indexOfAny(listOf("x"), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "indexOfAny"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for indexOfAny"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_indexOfAny_strings",
                    "Expected indexOfAny(strings, startIndex, ignoreCase) to resolve to kk_string_indexOfAny_strings"
                )
            }
        }
    }

    @Test func testLastIndexOfAnyCharsResolvesInCallExpressions() throws {
        let source = """
        fun lastAny(value: CharSequence, chars: CharArray): Int {
            return value.lastIndexOfAny(chars, 3, true)
        }

        fun stringLastAny(value: String): Int {
            return value.lastIndexOfAny(charArrayOf('x'), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndexOfAny"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for lastIndexOfAny"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_lastIndexOfAny_chars",
                    "Expected lastIndexOfAny(chars, startIndex, ignoreCase) to resolve to kk_string_lastIndexOfAny_chars"
                )
            }
        }
    }

    @Test func testLastIndexOfAnyStringsResolvesInCallExpressions() throws {
        let source = """
        fun lastAny(value: CharSequence, strings: Collection<String>): Int {
            return value.lastIndexOfAny(strings, 3, true)
        }

        fun stringLastAny(value: String): Int {
            return value.lastIndexOfAny(listOf("x"), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "lastIndexOfAny"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for lastIndexOfAny"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_lastIndexOfAny_strings",
                    "Expected lastIndexOfAny(strings, startIndex, ignoreCase) to resolve to kk_string_lastIndexOfAny_strings"
                )
            }
        }
    }

    @Test func testFindAnyOfStringsResolvesInCallExpressions() throws {
        let source = """
        fun findAny(value: CharSequence, strings: Collection<String>): Pair<Int, String>? {
            return value.findAnyOf(strings, 1, true)
        }

        fun stringFindAny(value: String): Pair<Int, String>? {
            return value.findAnyOf(listOf("x"), 0, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "findAnyOf"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for findAnyOf"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_findAnyOf",
                    "Expected findAnyOf(strings, startIndex, ignoreCase) to resolve to kk_string_findAnyOf"
                )
            }
        }
    }

    @Test func testFindLastAnyOfStringsResolvesInCallExpressions() throws {
        let source = """
        fun findLastAny(value: CharSequence, strings: Collection<String>): Pair<Int, String>? {
            return value.findLastAnyOf(strings, 3, true)
        }

        fun stringFindLastAny(value: String): Pair<Int, String>? {
            return value.findLastAnyOf(listOf("x"), 2, false)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "findLastAnyOf"
            }
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for findLastAnyOf"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_findLastAnyOf",
                    "Expected findLastAnyOf(strings, startIndex, ignoreCase) to resolve to kk_string_findLastAnyOf"
                )
            }
        }
    }

    @Test func testReplaceAfterResolvesInCallExpressions() throws {
        let source = """
        fun replaceAfterString(value: String): String {
            return value.replaceAfter(":", "tail", "missing")
        }

        fun replaceAfterStringDefault(value: String): String {
            return value.replaceAfter(":", "tail")
        }

        fun replaceAfterChar(value: String): String {
            return value.replaceAfter(':', "tail", "missing")
        }

        fun replaceAfterCharDefault(value: String): String {
            return value.replaceAfter(':', "tail")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceAfter"
            }
            #expect(callExprs.count == 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceAfter"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            #expect(links.filter { $0 == "kk_string_replaceAfter_flat" }.count == 2)
            #expect(links.filter { $0 == "kk_string_replaceAfter_char_flat" }.count == 2)
        }
    }

    @Test func testReplaceAfterLastResolvesInCallExpressions() throws {
        let source = """
        fun replaceAfterLastString(value: String): String {
            return value.replaceAfterLast(":", "tail", "missing")
        }

        fun replaceAfterLastStringDefault(value: String): String {
            return value.replaceAfterLast(":", "tail")
        }

        fun replaceAfterLastChar(value: String): String {
            return value.replaceAfterLast(':', "tail", "missing")
        }

        fun replaceAfterLastCharDefault(value: String): String {
            return value.replaceAfterLast(':', "tail")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceAfterLast"
            }
            #expect(callExprs.count == 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceAfterLast"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            #expect(links.filter { $0 == "kk_string_replaceAfterLast_flat" }.count == 2)
            #expect(links.filter { $0 == "kk_string_replaceAfterLast_char_flat" }.count == 2)
        }
    }

    @Test func testReplaceBeforeResolvesInCallExpressions() throws {
        let source = """
        fun replaceBeforeString(value: String): String {
            return value.replaceBefore(":", "head", "missing")
        }

        fun replaceBeforeStringDefault(value: String): String {
            return value.replaceBefore(":", "head")
        }

        fun replaceBeforeChar(value: String): String {
            return value.replaceBefore(':', "head", "missing")
        }

        fun replaceBeforeCharDefault(value: String): String {
            return value.replaceBefore(':', "head")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceBefore"
            }
            #expect(callExprs.count == 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceBefore"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            #expect(links.filter { $0 == "kk_string_replaceBefore_flat" }.count == 2)
            #expect(links.filter { $0 == "kk_string_replaceBefore_char_flat" }.count == 2)
        }
    }

    @Test func testReplaceBeforeLastResolvesInCallExpressions() throws {
        let source = """
        fun replaceBeforeLastString(value: String): String {
            return value.replaceBeforeLast(":", "head", "missing")
        }

        fun replaceBeforeLastStringDefault(value: String): String {
            return value.replaceBeforeLast(":", "head")
        }

        fun replaceBeforeLastChar(value: String): String {
            return value.replaceBeforeLast(':', "head", "missing")
        }

        fun replaceBeforeLastCharDefault(value: String): String {
            return value.replaceBeforeLast(':', "head")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceBeforeLast"
            }
            #expect(callExprs.count == 4)
            let links = try callExprs.map { callExpr -> String in
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected call binding for replaceBeforeLast"
                )
                return sema.symbols.externalLinkName(for: chosenCallee) ?? ""
            }
            #expect(links.filter { $0 == "kk_string_replaceBeforeLast_flat" }.count == 2)
            #expect(links.filter { $0 == "kk_string_replaceBeforeLast_char_flat" }.count == 2)
        }
    }

    @Test func testReplaceIndentByMarginResolvesInCallExpressions() throws {
        // MIGRATION-TEXT-006: replaceIndentByMargin is now a Kotlin stdlib function.
        // Verify it resolves to a valid callee without checking a C ABI link name.
        let source = """
        fun replaceIndentByMarginDefault(value: String): String {
            return value.replaceIndentByMargin()
        }

        fun replaceIndentByMarginNewIndent(value: String): String {
            return value.replaceIndentByMargin(">")
        }

        fun replaceIndentByMarginFull(value: String): String {
            return value.replaceIndentByMargin(">", "|")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "replaceIndentByMargin should resolve: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprs = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "replaceIndentByMargin"
            }
            #expect(callExprs.count == 3)
            for callExpr in callExprs {
                #expect(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee != nil,
                    "Expected call binding for replaceIndentByMargin"
                )
            }
        }
    }

    @Test func testAppendableInterfaceSurfaceResolves() throws {
        let source = """
        import kotlin.text.Appendable
        import kotlin.text.StringBuilder

        fun appendPieces(target: Appendable): Appendable {
            target.append('a')
            target.append("bc")
            return target.append("def", 1, 3)
        }

        fun builderAsAppendable(): Appendable {
            return StringBuilder()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Appendable surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let appendableFQName = ["kotlin", "text", "Appendable"].map { ctx.interner.intern($0) }
            let appendableSymbol = try #require(sema.symbols.lookup(fqName: appendableFQName))
            #expect(sema.symbols.symbol(appendableSymbol)?.kind == .interface)

            let appendableType = sema.types.make(.classType(ClassType(
                classSymbol: appendableSymbol,
                args: [],
                nullability: .nonNull
            )))
            // Filter to only user code's append calls on Appendable receiver
            // (bundled stdlib also has StringBuilder.append calls)
            let allAppendCalls = allExprIDs(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "append"
            }
            let appendCalls = allAppendCalls.filter { callExpr in
                guard let binding = sema.bindings.callBinding(for: callExpr),
                      let signature = sema.symbols.functionSignature(for: binding.chosenCallee)
                else { return false }
                return signature.receiverType == appendableType
            }
            #expect(appendCalls.count == 3)
            for callExpr in appendCalls {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected Appendable.append call binding"
                )
                let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                #expect(signature.receiverType == appendableType)
            }
        }
    }

    @Test func testTypographyObjectSurfaceResolves() throws {
        let source = """
        import kotlin.text.Typography

        fun typographyMarks(): Char {
            val nbsp: Char = Typography.nbsp
            val ellipsis: Char = Typography.ellipsis
            val guillemet: Char = Typography.leftGuillemet
            val legacyGuillemet: Char = Typography.leftGuillemete
            return Typography.greaterOrEqual
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Typography surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let typographyFQName = ["kotlin", "text", "Typography"].map { ctx.interner.intern($0) }
            let typographySymbol = try #require(sema.symbols.lookup(fqName: typographyFQName))
            #expect(sema.symbols.symbol(typographySymbol)?.kind == .object)

            let expectedConstants: [String: UInt32] = [
                "almostEqual": 0x2248,
                "amp": 0x0026,
                "bullet": 0x2022,
                "cent": 0x00A2,
                "copyright": 0x00A9,
                "dagger": 0x2020,
                "degree": 0x00B0,
                "dollar": 0x0024,
                "doubleDagger": 0x2021,
                "doublePrime": 0x2033,
                "ellipsis": 0x2026,
                "euro": 0x20AC,
                "greater": 0x003E,
                "greaterOrEqual": 0x2265,
                "half": 0x00BD,
                "leftDoubleQuote": 0x201C,
                "leftGuillemet": 0x00AB,
                "leftGuillemete": 0x00AB,
                "leftSingleQuote": 0x2018,
                "less": 0x003C,
                "lessOrEqual": 0x2264,
                "lowDoubleQuote": 0x201E,
                "lowSingleQuote": 0x201A,
                "mdash": 0x2014,
                "middleDot": 0x00B7,
                "nbsp": 0x00A0,
                "ndash": 0x2013,
                "notEqual": 0x2260,
                "paragraph": 0x00B6,
                "plusMinus": 0x00B1,
                "pound": 0x00A3,
                "prime": 0x2032,
                "quote": 0x0022,
                "registered": 0x00AE,
                "rightDoubleQuote": 0x201D,
                "rightGuillemet": 0x00BB,
                "rightGuillemete": 0x00BB,
                "rightSingleQuote": 0x2019,
                "section": 0x00A7,
                "times": 0x00D7,
                "tm": 0x2122,
            ]

            for (name, scalar) in expectedConstants {
                let propertyFQName = typographyFQName + [ctx.interner.intern(name)]
                let propertySymbol = try #require(sema.symbols.lookup(fqName: propertyFQName))
                #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.make(.primitive(.char, .nonNull)))
                #expect(sema.symbols.symbol(propertySymbol)?.flags.contains(.constValue) ?? false)
                guard case let .charLiteral(value) = sema.symbols.constValueExprKind(for: propertySymbol) else {
                    Issue.record("Expected Typography.\(name) to carry a char literal constant")
                    continue
                }
                #expect(value == scalar, "Unexpected Typography.\(name) scalar")
            }
        }
    }

    @Test func testCaseInsensitiveOrderSurfaceResolves() throws {
        let source = """
        import kotlin.text.CASE_INSENSITIVE_ORDER

        fun caseInsensitiveComparator(): Comparator<String> {
            return CASE_INSENSITIVE_ORDER
        }

        fun compareIgnoringCase(): Int {
            return CASE_INSENSITIVE_ORDER.compare("alpha", "ALPHA")
        }

        fun sortIgnoringCase(values: List<String>): List<String> {
            return values.sortedWith(CASE_INSENSITIVE_ORDER)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CASE_INSENSITIVE_ORDER surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let propertyFQName = ["kotlin", "text", "CASE_INSENSITIVE_ORDER"].map { ctx.interner.intern($0) }
            let propertySymbol = try #require(sema.symbols.lookup(fqName: propertyFQName))
            #expect(
                sema.symbols.externalLinkName(for: propertySymbol) == "kk_string_case_insensitive_order"
            )

            let comparatorFQName = ["kotlin", "Comparator"].map { ctx.interner.intern($0) }
            let comparatorSymbol = try #require(sema.symbols.lookup(fqName: comparatorFQName))
            let expectedType = sema.types.make(.classType(ClassType(
                classSymbol: comparatorSymbol,
                args: [.invariant(sema.types.stringType)],
                nullability: .nonNull
            )))
            #expect(sema.symbols.propertyType(for: propertySymbol) == expectedType)
        }
    }

    @Test func testStringBuilderDeleteAtResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun deleteOne(): StringBuilder {
            return StringBuilder("abc").deleteAt(1)
        }

        fun deleteWithReceiver(): String {
            return with(StringBuilder("rust")) {
                deleteAt(1)
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.deleteAt surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let deleteAtBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_deleteAt"
            }
            #expect(deleteAtBindings.count == 2)
        }
    }

    @Test func testStringBuilderDeleteRangeResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun deleteMiddle(): StringBuilder {
            return StringBuilder("abcdef").deleteRange(1, 4)
        }

        fun deleteWithReceiver(): String {
            return with(StringBuilder("abcdef")) {
                deleteRange(2, 5)
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.deleteRange surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let deleteRangeBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_deleteRange"
            }
            #expect(deleteRangeBindings.count == 2)
        }
    }

    // STDLIB-TEXT-FN-005: appendRange
    @Test func testStringBuilderAppendRangeResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun appendMiddle(): StringBuilder {
            return StringBuilder("ab").appendRange("WXYZ", 1, 3)
        }

        fun appendWithReceiver(): String {
            return with(StringBuilder("ab")) {
                appendRange("WXYZ", 0, 2)
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.appendRange surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let appendRangeBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_appendRange_obj_flat"
            }
            #expect(appendRangeBindings.count == 2)
        }
    }

    // STDLIB-TEXT-FN-024: insert
    @Test func testStringBuilderInsertResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun insertMiddle(): StringBuilder {
            return StringBuilder("ac").insert(1, "b")
        }

        fun insertWithReceiver(): String {
            return with(StringBuilder("ac")) {
                insert(1, "b")
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.insert surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let insertBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_insert_obj"
            }
            #expect(insertBindings.count == 2)
        }
    }

    @Test func testStringBuilderInsertRangeResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun insertMiddle(): StringBuilder {
            return StringBuilder("ab").insertRange(1, "WXYZ", 1, 3)
        }

        fun insertWithReceiver(): String {
            return with(StringBuilder("ab")) {
                insertRange(2, "WXYZ", 0, 2)
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.insertRange surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let insertRangeBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_insertRange_obj_flat"
            }
            #expect(insertRangeBindings.count == 2)
        }
    }

    @Test func testStringBuilderSetRangeResolvesInCallExpressions() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun setMiddle(): StringBuilder {
            return StringBuilder("abcd").setRange(1, 3, "XYZ")
        }

        fun setWithReceiver(): String {
            return with(StringBuilder("abcd")) {
                setRange(0, 2, "XY")
                toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.setRange surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let setRangeBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_setRange_flat"
            }
            #expect(setRangeBindings.count == 2)
        }
    }

    @Test func testStringBuilderSetOperatorResolvesToSetCharAt() throws {
        // STDLIB-TEXT-FN-064: operator fun set(index, value) desugars to sb.set(i, c)
        let source = """
        import kotlin.text.StringBuilder

        fun replaceChar(): StringBuilder {
            val sb = StringBuilder("abc")
            sb.set(1, 'X')
            return sb
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected StringBuilder.set operator to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let setBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_builder_setCharAt"
            }
            #expect(setBindings.count >= 1)
        }
    }

    @Test func testCharSequenceZipWithNextMembersResolveInCallExpressions() throws {
        let source = """
        fun pairs(value: CharSequence): List<Pair<Char, Char>> {
            return value.zipWithNext()
        }

        fun labels(value: CharSequence): List<String> {
            return value.zipWithNext { a, b -> "" + a + b }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            var externalLinks: [String] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "zipWithNext",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                externalLinks.append(link)
            }

            #expect(
                externalLinks == ["kk_string_zipWithNext_flat", "kk_string_zipWithNextTransform_flat"]
            )
        }
    }

    @Test func testCharSequenceFirstNotNullOfResolvesInCallExpressions() throws {
        let source = """
        fun firstLabel(value: CharSequence): String {
            return value.firstNotNullOf<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun firstFromString(value: String): String {
            return value.firstNotNullOf<String> { ch -> if (ch == 'c') "see" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.firstNotNullOf surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let firstNotNullOfBindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_firstNotNullOf_flat"
            }
            #expect(firstNotNullOfBindings.count == 2)
        }
    }

    @Test func testCharSequenceFirstNotNullOfOrNullResolvesInCallExpressions() throws {
        let source = """
        fun firstLabel(value: CharSequence): String? {
            return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'b') "bee" else null }
        }

        fun firstFromString(value: String): String? {
            return value.firstNotNullOfOrNull<String> { ch -> if (ch == 'c') "see" else null }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.firstNotNullOfOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_firstNotNullOfOrNull_flat"
            }
            #expect(bindings.count == 2)
        }
    }

    @Test func testCharSequenceReduceRightIndexedResolvesInCallExpressions() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char {
            return value.reduceRightIndexed { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun reduceFromString(value: String): Char {
            return value.reduceRightIndexed { index, ch, acc -> if (index == 0) ch else acc }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.reduceRightIndexed surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_reduceRightIndexed"
            }
            #expect(bindings.count == 2)
        }
    }

    @Test func testCharSequenceReduceRightIndexedOrNullResolvesInCallExpressions() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 1) ch else acc }
        }

        fun reduceFromString(value: String): Char? {
            return value.reduceRightIndexedOrNull { index, ch, acc -> if (index == 0) ch else acc }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.reduceRightIndexedOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_reduceRightIndexedOrNull"
            }
            #expect(bindings.count == 2)
        }
    }

    @Test func testCharSequenceReduceRightOrNullResolvesInCallExpressions() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceRightOrNull { ch, acc -> if (ch == 'b') ch else acc }
        }

        fun reduceFromString(value: String): Char? {
            return value.reduceRightOrNull { ch, acc -> if (ch == 'a') ch else acc }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.reduceRightOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_reduceRightOrNull"
            }
            #expect(bindings.count == 2)
        }
    }

    @Test func testCharSequenceSumByResolvesInCallExpressions() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Int {
            return value.sumBy { if (it == 'a') 10 else 1 }
        }

        fun sumFromString(value: String): Int {
            return value.sumBy { ch -> if (ch == 'b') 20 else 2 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.sumBy surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_sumBy"
            }
            #expect(bindings.count == 2)
            let sumBySymbol = try #require(bindings.first?.chosenCallee)
            #expect(
                sema.symbols.annotations(for: sumBySymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "CharSequence.sumBy should carry Deprecated metadata"
            )
        }
    }

    @Test func testCharSequenceSumByDoubleResolvesInCallExpressions() throws {
        let source = """
        fun sumFromSequence(value: CharSequence): Double {
            return value.sumByDouble { if (it == 'a') 1.5 else 0.25 }
        }

        fun sumFromString(value: String): Double {
            return value.sumByDouble { ch -> if (ch == 'b') 2.0 else 0.5 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.sumByDouble surface to resolve cleanly, got: \(diagnosticSummary)"
            )

            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_sumByDouble"
            }
            #expect(bindings.count == 2)
            let sumByDoubleSymbol = try #require(bindings.first?.chosenCallee)
            #expect(
                sema.symbols.annotations(for: sumByDoubleSymbol).contains { $0.annotationFQName == "kotlin.Deprecated" },
                "CharSequence.sumByDouble should carry Deprecated metadata"
            )
        }
    }

    @Test func testByteArrayDecodeToStringRangeMembersResolveInCallExpressions() throws {
        let source = """
        fun decode(bytes: ByteArray): String {
            val sliced = bytes.decodeToString(1, 4)
            val strict = bytes.decodeToString(0, 4, true)
            return sliced + strict
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "decodeToString"
                else {
                    return nil
                }
                return exprID
            }
            #expect(callExprIDs.count == 2, "Expected two decodeToString range calls")

            // After MIGRATION-TEXT-007, ByteArray.decodeToString range/range+throw variants are
            // defined in BundledKotlinStdlib Kotlin source (not synthetic stubs), so they have
            // no externalLinkName. The C bridge is called internally via __kk_decodeToString_range.
            for (index, callExprID) in callExprIDs.enumerated() {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExprID)?.chosenCallee,
                    "Expected call binding for decodeToString overload \(index)"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "kotlin.text.decodeToString range overload \(index) should resolve to Kotlin-source (no externalLinkName after migration)"
                )
            }
        }
    }

    @Test func testCharSequenceWithIndexResolvesInCallExpressions() throws {
        let source = """
        fun indexed(value: CharSequence) = value.withIndex()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected CharSequence.withIndex to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let callExprIDs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "withIndex"
                else {
                    return nil
                }
                return exprID
            }

            let chosenCalleeCandidate = callExprIDs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }.first
            let chosenCallee = try #require(chosenCalleeCandidate)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_withIndex_flat")
        }
    }

    // STDLIB-TEXT-FN-116: CharSequence.zip(other) / zip(other, transform)
    @Test func testCharSequenceZipMembersResolveInCallExpressions() throws {
        let source = """
        fun pairs(value: CharSequence, other: CharSequence): List<Pair<Char, Char>> {
            return value.zip(other)
        }

        fun labels(value: CharSequence, other: CharSequence): List<String> {
            return value.zip(other) { a, b -> "" + a + b }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            var externalLinks: [String] = []
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, callee, _, _, _) = expr,
                      ctx.interner.resolve(callee) == "zip",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                externalLinks.append(link)
            }

            #expect(
                externalLinks == ["kk_string_zip_flat", "kk_string_zipTransform_flat"]
            )
        }
    }

    @Test func testCharSequenceReduceOrNullResolvesInCallExpressions() throws {
        let source = """
        fun reduceFromSequence(value: CharSequence): Char? {
            return value.reduceOrNull { acc, ch -> if (ch == 'b') ch else acc }
        }
        fun reduceFromString(value: String): Char? {
            return value.reduceOrNull { acc, ch -> if (acc == 'a') acc else ch }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnosticSummary = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected CharSequence.reduceOrNull surface to resolve cleanly, got: \(diagnosticSummary)"
            )
            let sema = try #require(ctx.sema)
            let bindings = sema.bindings.callBindings.values.filter { binding in
                sema.symbols.externalLinkName(for: binding.chosenCallee) == "kk_string_reduceOrNull"
            }
            #expect(bindings.count == 2)
        }
    }
}
