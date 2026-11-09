import Foundation

import CompilerCore

struct CodegenStackTraceFunctionMetadata {
    let className: String
    let methodName: String
    let initialFileName: String
    let initialLine: Int
}

enum CodegenSymbolSupport {
    static func fileFacadeNames(from ast: ASTModule?) -> [Int32: String] {
        guard let ast else {
            return [:]
        }
        return ast.files.reduce(into: [:]) { partial, file in
            guard let name = fileFacadeName(for: file) else {
                return
            }
            partial[file.fileID.rawValue] = name
        }
    }

    static func fileFacadeName(for file: ASTFile) -> String? {
        for annotation in file.annotations where annotation.useSiteTarget == "file" {
            guard KnownCompilerAnnotation.jvmName.matches(annotation.name),
                  let firstArgument = annotation.arguments.first
            else {
                continue
            }
            let trimmed = firstArgument.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func cFunctionSymbol(
        for function: KIRFunction,
        interner: StringInterner,
        moduleName: String = "main",
        symbols: SymbolTable? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:]
    ) -> String {
        let rawName = jvmFunctionName(for: function, symbols: symbols)
            ?? interner.resolve(function.name)
        let facadePrefix = if let fileID = function.sourceRange?.start.file.rawValue,
                              let facadeName = fileFacadeNamesByFileID[fileID],
                              !facadeName.isEmpty
        {
            "\(sanitizeForCSymbol(facadeName))_"
        } else {
            ""
        }
        let safeName = sanitizeForCSymbol(rawName)
        // Synthetic symbols are negative; the `s` marker keeps them from sharing
        // a C name with a same-named real symbol of equal magnitude.
        let raw = function.symbol.rawValue
        let suffix = raw < 0 ? "s\(raw.magnitude)" : "\(raw)"
        let fqName = symbols?.symbol(function.symbol)?.fqName.map { interner.resolve($0) } ?? []
        let namespace = ([moduleName] + fqName).map(encodeNamespaceComponent).joined(separator: "_")
        return "kk_fn_\(facadePrefix)\(safeName)_\(suffix)__\(namespace)"
    }

    static func stackTraceMetadata(
        for function: KIRFunction,
        interner: StringInterner,
        symbols: SymbolTable?,
        sourceManager: SourceManager?,
        fileFacadeNamesByFileID: [Int32: String]
    ) -> CodegenStackTraceFunctionMetadata {
        let symbol = symbols?.symbol(function.symbol)
        let methodName: String
        if symbol?.kind == .constructor {
            methodName = "<init>"
        } else {
            methodName = jvmFunctionName(for: function, symbols: symbols)
                ?? symbol.map { interner.resolve($0.name) }
                ?? interner.resolve(function.name)
        }

        var packageName: String?
        var ownerName: String?
        if let symbols, let symbol {
            var parent = symbols.parentSymbolIfKnown(for: symbol.id)
            while let parentID = parent, let parentSymbol = symbols.symbol(parentID) {
                switch parentSymbol.kind {
                case .class, .interface, .enumClass, .object:
                    if !symbol.flags.contains(.extensionMemberAlias) {
                        ownerName = parentSymbol.fqName.map(interner.resolve).joined(separator: ".")
                    }
                case .package:
                    packageName = parentSymbol.fqName.map(interner.resolve).joined(separator: ".")
                default:
                    break
                }
                if ownerName != nil || packageName != nil {
                    break
                }
                parent = symbols.parentSymbolIfKnown(for: parentID)
            }
            if packageName == nil,
               ownerName == nil,
               !symbol.flags.contains(.localFunction),
               !symbol.flags.contains(.extensionMemberAlias),
               symbol.fqName.count > 1
            {
                packageName = symbol.fqName.dropLast().map(interner.resolve).joined(separator: ".")
            }
        }

        let sourceFileID = function.sourceRange?.start.file.rawValue
        let filePath = sourceFileID.flatMap { rawValue in
            sourceManager?.path(of: FileID(rawValue: rawValue))
        }
        let fileName = filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown Source"

        let className: String
        if let ownerName, !ownerName.isEmpty {
            className = ownerName
        } else {
            let facadeName: String
            if let sourceFileID, let explicitFacade = fileFacadeNamesByFileID[sourceFileID], !explicitFacade.isEmpty {
                facadeName = explicitFacade
            } else if fileName != "Unknown Source" {
                facadeName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent + "Kt"
            } else {
                facadeName = "UnknownKt"
            }
            className = [packageName, facadeName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ".")
        }

        let initialLocation = function.sourceRange.flatMap { range in
            sourceManager?.lineColumn(of: range.start)
        }
        return CodegenStackTraceFunctionMetadata(
            className: className.isEmpty ? "main.UnknownKt" : className,
            methodName: methodName,
            initialFileName: fileName,
            initialLine: initialLocation?.line ?? 0
        )
    }

    // Encode bytes rather than sanitizing: e.g. `a-b` and `a_b` must stay distinct.
    private static func encodeNamespaceComponent(_ text: String) -> String {
        "\(text.utf8.count)x" + text.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private static func jvmFunctionName(
        for function: KIRFunction,
        symbols: SymbolTable?
    ) -> String? {
        guard let symbols else {
            return nil
        }
        for annotation in symbols.annotations(for: function.symbol) {
            guard KnownCompilerAnnotation.jvmName.matches(annotation.annotationFQName),
                  let firstArgument = annotation.arguments.first
            else {
                continue
            }
            let trimmed = firstArgument.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func sanitizeForCSymbol(_ text: String) -> String {
        if text.isEmpty {
            return "_"
        }
        var result = ""
        for (index, scalar) in text.unicodeScalars.enumerated() {
            let isAlphaNum = CharacterSet.alphanumerics.contains(scalar)
            if index == 0 {
                if CharacterSet.letters.contains(scalar) || scalar == "_" {
                    result.append(Character(scalar))
                } else if isAlphaNum {
                    result.append("_")
                    result.append(Character(scalar))
                } else {
                    result.append("_")
                }
            } else if isAlphaNum || scalar == "_" {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        if result.isEmpty {
            return "_"
        }
        return result
    }
}
