#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

/// Pinned API declarations are checked independently of their execution-test results.
/// KLIB property/getter and PublishedApi duplicates are views of one semantic symbol.
@Suite
struct ByteStringAPIShapeTests {
    private struct Index: Decodable {
        let schemaVersion: Int
        let upstreamCommit: String
        let rowCount: Int
        let canonicalRecordCount: Int
        let rows: [Row]
    }

    private struct Row: Decodable {
        let rowID: String
        let canonicalKey: String
        let upstreamRef: String
        let fqName: String
        let kind: String
        let visibility: String
        let receiverKind: String
        let receiverTypeSignature: String?
        let typeSignature: String?
        let parameterNames: [String]
        let parameterTypeSignatures: [String]
        let vararg: [Bool]
        let defaults: [Bool]
        let inline: Bool
        let operatorDeclared: Bool
        let `override`: Bool
        let typeParameterNames: [String]
        let typeParameterBounds: [[String]]
        let nonLocalCallbackIndices: [Int]
        let callsInPlace: [String]
        let callsInPlaceParameterIndices: [Int]
        let annotations: [Annotation]
        let superFQNames: [String]
        let genericSuperSignatures: [String]
        let getterSignature: String?
    }

    private struct Annotation: Decodable {
        struct Argument: Decodable {
            let name: String?
            let kind: String
            let value: String
        }

        let fqName: String
        let sourceOnly: Bool
        let arguments: [Argument]
    }

    @Test(arguments: [false, true])
    func allPinnedCommonNativeAPIShapesMatch(allowDefaultStdlibLibrary: Bool) throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/kotlinx_io_upstream/bytestring/api-shapes.expected.json")
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture))
        #expect(index.schemaVersion == 1)
        #expect(index.upstreamCommit == "362bdc35e159bad6da1e08101c8321792d762281")
        #expect(index.rowCount == 65 && index.rows.count == 65)
        #expect(Set(index.rows.map(\.rowID)).count == 65)
        #expect(Set(index.rows.map(\.canonicalKey)).count == index.canonicalRecordCount)
        #expect(index.canonicalRecordCount == 60)

        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let ctx = makeContextFromSource("fun main() = 0", allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        var importedRecords: [MetadataRecord] = []
        if allowDefaultStdlibLibrary {
            let path = try #require(ctx.options.stdlibLibraryPath, "Library mode cannot fall back to bundled source")
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let manifestData = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
            let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            #expect(manifest["moduleName"] as? String == "KSwiftKStdlib")
            #expect(manifest["formatVersion"] as? Int == 1)
            #expect(manifest["kotlinVersion"] as? String == "2.3.10")
            let metadata = try String(contentsOf: directory.appendingPathComponent("metadata.bin"), encoding: .utf8)
            importedRecords = MetadataDecoder().decode(metadata)
            #expect(!importedRecords.isEmpty, "Cached artifact must contain decodable metadata")
        } else {
            #expect(ctx.options.stdlibLibraryPath == nil)
            #expect(ctx.options.includeStdlib)
        }
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let mangler = NameMangler()
        let symbols = sema.symbols
        let resolve: (InternedString) -> String = { ctx.interner.resolve($0) }
        let importedGroups = Dictionary(grouping: importedRecords, by: \.fqName)
        var matched = Set<SymbolID>()

        func encode(_ type: TypeID) -> String {
            mangler.encodeType(type, symbols: symbols, types: sema.types, nameResolver: resolve, unboxValueClasses: false)
        }
        func normalize(_ encoded: String, _ parameters: [SymbolID]) -> String {
            // Tokens are matched as complete numbers: T12 must never rewrite T123.
            let replacements = Dictionary(uniqueKeysWithValues: parameters.enumerated().map { ("T\($0.element.rawValue)", "T\($0.offset)") })
            let regex = try! NSRegularExpression(pattern: "T[0-9]+")
            let range = NSRange(encoded.startIndex..., in: encoded)
            var result = encoded
            for match in regex.matches(in: encoded, range: range).reversed() {
                guard let tokenRange = Range(match.range, in: encoded),
                      let replacement = replacements[String(encoded[tokenRange])],
                      let resultRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(resultRange, with: replacement)
            }
            return result
        }
        func signature(_ symbol: SemanticSymbol) -> String? {
            guard [.function, .constructor, .property].contains(symbol.kind) else { return nil }
            let params = symbols.functionSignature(for: symbol.id)?.typeParameterSymbols ?? []
            return normalize(mangler.mangledSignature(for: symbol, symbols: symbols, types: sema.types,
                                                     nameResolver: resolve, unboxValueClasses: false), params)
        }
        func receiverSignature(_ symbol: SemanticSymbol) -> String? {
            if symbol.kind == .property { return symbols.extensionPropertyReceiverType(for: symbol.id).map(encode) }
            return symbols.functionSignature(for: symbol.id)?.receiverType.map(encode)
        }

        for row in index.rows {
            let candidates = symbols.lookupAll(fqName: row.fqName.split(separator: ".").map { ctx.interner.intern(String($0)) })
                .compactMap { symbols.symbol($0) }
                .filter { String(describing: $0.kind) == row.kind && !$0.flags.contains(.extensionMemberAlias)
                    && signature($0) == row.typeSignature }
            #expect(candidates.count == 1, "\(row.rowID) \(row.upstreamRef): expected one \(row.canonicalKey), got \(candidates.count)")
            let symbol = try #require(candidates.first, "Missing \(row.rowID): \(row.canonicalKey)")
            matched.insert(symbol.id)
            #expect(String(describing: symbol.visibility) == row.visibility, "\(row.rowID) visibility")
            #expect(symbol.flags.contains(.importedLibrary) == allowDefaultStdlibLibrary,
                    "\(row.rowID) must use the requested source/library mode")
            #expect(!symbol.flags.contains(.memberExtension), "\(row.rowID) is not a member extension")
            if row.kind != "property" {
                #expect(receiverSignature(symbol) == row.receiverTypeSignature, "\(row.rowID) receiver")
            } else if row.receiverKind == "PACKAGE_EXTENSION" {
                #expect(receiverSignature(symbol) == row.receiverTypeSignature, "\(row.rowID) extension property receiver")
            } else {
                #expect(symbols.extensionPropertyReceiverType(for: symbol.id) == nil, "\(row.rowID) member property")
                #expect(symbol.fqName.dropLast().map(resolve).joined(separator: ".") == "kotlinx.io.bytestring."
                    + (row.fqName.contains("ByteStringBuilder") ? "ByteStringBuilder" : "ByteString"))
            }

            if row.kind == "function" || row.kind == "constructor" {
                let fn = try #require(symbols.functionSignature(for: symbol.id))
                #expect(fn.parameterTypes.map(encode).map { normalize($0, fn.typeParameterSymbols) } == row.parameterTypeSignatures,
                        "\(row.rowID) parameter types")
                #expect(fn.valueParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.parameterNames,
                        "\(row.rowID) formal names")
                #expect(fn.valueParameterIsVararg == row.vararg, "\(row.rowID) vararg flags")
                #expect(fn.valueParameterHasDefaultValues == row.defaults, "\(row.rowID) default flags")
                #expect(symbol.flags.contains(.inlineFunction) == row.inline, "\(row.rowID) inline")
                #expect(symbol.flags.contains(.operatorFunction) == row.operatorDeclared, "\(row.rowID) declared operator")
                #expect(symbol.flags.contains(.overrideMember) == row.override, "\(row.rowID) override")
                #expect(!fn.isSuspend && !symbol.flags.contains(.infixFunction), "\(row.rowID) suspend/infix")
                #expect(fn.typeParameterSymbols.count == row.typeParameterNames.count, "\(row.rowID) type parameter count")
                if !allowDefaultStdlibLibrary {
                    #expect(fn.typeParameterSymbols.compactMap { symbols.symbol($0).map { resolve($0.name) } } == row.typeParameterNames,
                            "\(row.rowID) source type parameter names")
                }
                #expect(fn.typeParameterUpperBoundsList.map { $0.map { normalize(encode($0), fn.typeParameterSymbols) } } == row.typeParameterBounds,
                        "\(row.rowID) type parameter bounds")
                for parameterIndex in row.nonLocalCallbackIndices {
                    #expect(parameterIndex < fn.valueParameterAllowsNonLocalReturn.count
                        && fn.valueParameterAllowsNonLocalReturn[parameterIndex], "\(row.rowID) inline callback permission")
                }
                let effects = symbols.contractCallsInPlaceEffects(for: symbol.id)
                let actualKinds = effects.compactMap { effect -> String? in
                    guard fn.valueParameterSymbols.contains(effect.parameterSymbol) else { return nil }
                    switch effect.kind {
                    case .exactlyOnce: return "EXACTLY_ONCE"
                    case .atMostOnce: return "AT_MOST_ONCE"
                    case .atLeastOnce: return "AT_LEAST_ONCE"
                    case .unknown: return "UNKNOWN"
                    }
                }
                #expect(actualKinds == row.callsInPlace, "\(row.rowID) callsInPlace kind")
                #expect(effects.compactMap { fn.valueParameterSymbols.firstIndex(of: $0.parameterSymbol) } == row.callsInPlaceParameterIndices,
                        "\(row.rowID) callsInPlace formal")
            }

            if row.kind == "property" {
                #expect(!symbol.flags.contains(.mutable), "\(row.rowID) read-only property")
                let type = try #require(symbols.propertyType(for: symbol.id))
                let getter = "F0<" + (row.receiverTypeSignature.map { "R" + $0 + "," } ?? "") + encode(type) + ">"
                #expect(getter == row.getterSignature, "\(row.rowID) getter contract represented by property")
            }
            if !row.superFQNames.isEmpty {
                #expect(!symbol.flags.contains(.openType), "\(row.rowID) nominal finality")
                let supers = symbols.directSupertypes(for: symbol.id)
                #expect(supers.compactMap { symbols.symbol($0)?.fqName.map(resolve).joined(separator: ".") }.sorted() == row.superFQNames.sorted(),
                        "\(row.rowID) direct supertypes")
                let genericSupers = supers.compactMap { parent -> String? in
                    let args = sema.types.nominalSupertypeTypeArgs(for: symbol.id, supertype: parent)
                    guard !args.isEmpty else { return nil }
                    return encode(sema.types.make(.classType(ClassType(classSymbol: parent, args: args, nullability: .nonNull))))
                }
                #expect(genericSupers.sorted() == row.genericSuperSignatures.sorted(), "\(row.rowID) generic supertypes")
            }
            try checkAnnotations(symbols.annotations(for: symbol.id), row: row, imported: allowDefaultStdlibLibrary)

            if allowDefaultStdlibLibrary {
                let records = (importedGroups[row.fqName] ?? []).filter { record in
                    String(describing: record.kind) == row.kind
                        && normalizeWireSignature(record.typeSignature, parameters: record.callableTypeParameterSignatures) == row.typeSignature
                }
                #expect(records.count == 1, "\(row.rowID) one emitted canonical record")
                let record = try #require(records.first)
                if row.kind == "property" {
                    #expect(record.propertyGetterExternalLinkName?.isEmpty == false, "\(row.rowID) emitted getter link")
                    #expect(record.propertySetterExternalLinkName == nil, "\(row.rowID) no setter")
                    #expect(record.propertyReceiverTypeSignature == (row.receiverKind == "PACKAGE_EXTENSION" ? row.receiverTypeSignature : nil))
                }
                if row.defaults.contains(true) {
                    #expect(record.defaultStubExternalLinkName?.isEmpty == false, "\(row.rowID) emitted default stub")
                }
            }
        }
        #expect(matched.count == 60, "The 65 ledger views map to exactly 60 semantic declarations")
        let declaredAPIs = symbols.allSymbols().filter { symbol in
            let fq = symbol.fqName.map(resolve).joined(separator: ".")
            guard fq.hasPrefix("kotlinx.io.bytestring."),
                  symbol.visibility == .public || symbol.visibility == .protected || fq == "kotlinx.io.bytestring.ByteString.getBackingArrayReference",
                  [.function, .constructor, .property, .class, .interface, .annotationClass, .object, .enumClass, .typeAlias].contains(symbol.kind),
                  !symbol.flags.contains(.extensionMemberAlias),
                  symbols.propertySymbol(forAccessor: symbol.id) == nil,
                  symbols.accessorOwnerProperty(for: symbol.id) == nil else { return false }
            // Annotation Any members are inherited compiler-generated surface, not upstream declarations.
            return !["equals", "hashCode", "toString"].contains(fq.replacingOccurrences(of: "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi.", with: ""))
                || !fq.hasPrefix("kotlinx.io.bytestring.unsafe.UnsafeByteStringApi.")
        }
        #expect(Set(declaredAPIs.map(\.id)) == matched,
                "Unexpected/missing API declarations: \(declaredAPIs.filter { !matched.contains($0.id) }.map { $0.fqName.map(resolve).joined(separator: ".") })")
    }

    private func normalizeWireSignature(_ signature: String?, parameters: [String]) -> String? {
        guard var result = signature else { return nil }
        let regex = try! NSRegularExpression(pattern: "T[0-9]+")
        let original = result
        for match in regex.matches(in: original, range: NSRange(original.startIndex..., in: original)).reversed() {
            guard let range = Range(match.range, in: original),
                  let index = parameters.firstIndex(of: String(original[range])),
                  let resultRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(resultRange, with: "T\(index)")
        }
        return result
    }

    private func checkAnnotations(_ actual: [MetadataAnnotationRecord], row: Row, imported: Bool) throws {
        let expected = row.annotations.filter { !imported || !$0.sourceOnly }
        let apiAnnotations = actual.filter { $0.annotationFQName != "kotlin.Metadata" && $0.annotationFQName != "kotlin.OptIn" }
        #expect(Set(apiAnnotations.map(\.annotationFQName)) == Set(expected.filter { !$0.sourceOnly }.map(\.fqName)),
                "\(row.rowID) exact declaration annotations")
        for annotation in expected {
            let values = actual.filter { $0.annotationFQName == annotation.fqName }
            #expect(values.count == 1, "\(row.rowID) annotation \(annotation.fqName)")
            let value = try #require(values.first)
            #expect(value.useSiteTarget == nil, "\(row.rowID) annotation owner target")
            #expect(value.arguments.count == annotation.arguments.count, "\(row.rowID) annotation arguments")
            for (argument, observed) in zip(annotation.arguments, value.arguments) {
                var text = observed
                if let equals = text.firstIndex(of: "=") {
                    if let name = argument.name { #expect(String(text[..<equals]) == name, "\(row.rowID) named annotation argument") }
                    text = String(text[text.index(after: equals)...])
                }
                switch argument.kind {
                case "string":
                    // These pinned string constants contain no quote/plus characters. The
                    // compiler may serialize a constant concat expression instead of folding it.
                    let flattened = text.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "+", with: "")
                    #expect(flattened == argument.value, "\(row.rowID) full annotation string")
                case "enum", "classLiteral":
                    text = text.replacingOccurrences(of: "::class", with: "")
                    let canonical = argument.value.replacingOccurrences(of: "kotlin.annotation.", with: "").replacingOccurrences(of: "kotlin.contracts.", with: "").replacingOccurrences(of: "kotlin.", with: "")
                    #expect(text == argument.value || text == canonical, "\(row.rowID) annotation enum/class value")
                default:
                    #expect(text == argument.value, "\(row.rowID) annotation value")
                }
            }
        }
    }
}
#endif
