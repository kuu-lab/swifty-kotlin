import Foundation

/// Layout (Kotlin `KlibIrComponentImpl`):
/// - `ir/files.knf` — `IrFile` per serialized source file.
/// - `ir/irDeclarations.knd` — `[file][declarationId]` → `IrDeclaration`.
/// - `ir/bodies.knb` — `[file][bodyIndex]` → `IrStatement`.
/// - `ir/types.knt`, `ir/signatures.knt`, `ir/strings.knt` —
///   `[file][index]` → `IrType` / `IdSignature` / UTF-8 string.
/// - `ir/fileEntries.knf` — `[file][entryIndex]` → `FileEntry`
///   (entries used by inlined bodies; the file's own entry is either
///   embedded in `IrFile.file_entry` or referenced via `file_entry_id`).
/// - `ir/debugInfo.knd` — `[file][index]` → UTF-8 signature debug string.
///
/// A klib without serialized IR (e.g. cinterop artifacts) has `hasIR ==
/// false` and no files.
package struct KlibIrModule {
    package static let irDirectory = "ir"

    package let container: KlibContainer

    private let files: KlibIrTable?
    private let fileEntries: KlibIrMultiTable?
    private let declarations: KlibIrDeclarationMultiTable?
    private let bodies: KlibIrMultiTable?
    private let types: KlibIrMultiTable?
    private let signatures: KlibIrMultiTable?
    private let strings: KlibIrMultiTable?
    private let signatureDebugInfos: KlibIrMultiTable?

    package init(container: KlibContainer) throws {
        self.container = container
        func read(_ name: String) throws -> [UInt8]? {
            let path = "\(Self.irDirectory)/\(name)"
            guard container.contains(path) else { return nil }
            return try container.read(path)
        }
        files = try read("files.knf").map { try KlibIrTable(bytes: $0) }
        fileEntries = try read("fileEntries.knf").map { try KlibIrMultiTable(bytes: $0) }
        declarations = try read("irDeclarations.knd").map { try KlibIrDeclarationMultiTable(bytes: $0) }
        bodies = try read("bodies.knb").map { try KlibIrMultiTable(bytes: $0) }
        types = try read("types.knt").map { try KlibIrMultiTable(bytes: $0) }
        signatures = try read("signatures.knt").map { try KlibIrMultiTable(bytes: $0) }
        strings = try read("strings.knt").map { try KlibIrMultiTable(bytes: $0) }
        signatureDebugInfos = try read("debugInfo.knd").map { try KlibIrMultiTable(bytes: $0) }

        let requiredTables: [(String, Int?)] = [
            ("irDeclarations.knd", declarations?.fileCount),
            ("bodies.knb", bodies?.rowCount),
            ("types.knt", types?.rowCount),
            ("signatures.knt", signatures?.rowCount),
            ("strings.knt", strings?.rowCount),
        ]
        guard let files else {
            guard requiredTables.allSatisfy({ $0.1 == nil }),
                  fileEntries == nil, signatureDebugInfos == nil else {
                throw KlibFormatError.corruptChunk("IR tables exist without files.knf")
            }
            return
        }
        for (name, rows) in requiredTables {
            guard rows == files.count else {
                throw KlibFormatError.corruptChunk("\(name) must have one row per IR file")
            }
        }
        for (name, rows) in [("fileEntries.knf", fileEntries?.rowCount), ("debugInfo.knd", signatureDebugInfos?.rowCount)] {
            if let rows, rows != files.count {
                throw KlibFormatError.corruptChunk("\(name) must have one row per IR file")
            }
        }
    }

    package var hasIR: Bool { files != nil }

    package var fileCount: Int { files?.count ?? 0 }

    package func file(_ fileIndex: Int) throws -> KlibIrFile {
        guard let files else { throw KlibFormatError.corruptChunk("no files table") }
        return try KlibIrDecoding.file(ProtoFields(files.element(fileIndex)))
    }

    /// Top-level declarations of `fileIndex`, in `declaration_id` order.
    package func declarations(fileIndex: Int) throws -> [KlibIrDeclaration] {
        try file(fileIndex).declarationIds.map { try declaration($0, fileIndex: fileIndex) }
    }

    package func declaration(_ declarationId: Int32, fileIndex: Int) throws -> KlibIrDeclaration {
        guard let declarations else { throw KlibFormatError.corruptChunk("no declarations table") }
        return try KlibIrDecoding.declaration(ProtoFields(declarations.element(fileIndex: fileIndex, declarationId: declarationId)))
    }

    /// `bodies` element — an `IrStatement` message (typically wrapping
    /// `IrBlockBody` for function bodies).
    package func body(_ bodyIndex: Int32, fileIndex: Int) throws -> KlibIrStatement {
        guard let bodies else { throw KlibFormatError.corruptChunk("no bodies table") }
        return try KlibIrDecoding.statement(ProtoFields(bodies.element(row: fileIndex, column: Int(bodyIndex))))
    }

    /// `bodies` element decoded as a bare `IrExpression` — the payload stored
    /// for `IrField.initializer`, `IrEnumEntry.initializer` and
    /// `IrValueParameter.defaultValue` (`deserializeExpressionBody`).
    package func expressionBody(_ bodyIndex: Int32, fileIndex: Int) throws -> KlibIrExpression {
        guard let bodies else { throw KlibFormatError.corruptChunk("no bodies table") }
        return try KlibIrDecoding.expression(ProtoFields(bodies.element(row: fileIndex, column: Int(bodyIndex))))
    }

    package func type(_ typeIndex: Int32, fileIndex: Int) throws -> KlibIrType {
        guard let types else { throw KlibFormatError.corruptChunk("no types table") }
        return try KlibIrDecoding.type(ProtoFields(types.element(row: fileIndex, column: Int(typeIndex))))
    }

    package func signature(_ signatureIndex: Int, fileIndex: Int) throws -> KlibIdSignature {
        guard let signatures else { throw KlibFormatError.corruptChunk("no signatures table") }
        return try KlibIrDecoding.idSignature(ProtoFields(signatures.element(row: fileIndex, column: signatureIndex)))
    }

    package func publicSignature(_ signatureIndex: Int, fileIndex: Int) throws -> KlibPublicSignature? {
        try publicSignature(signatureIndex, fileIndex: fileIndex, depth: 0)
    }

    private func publicSignature(_ signatureIndex: Int, fileIndex: Int, depth: Int) throws -> KlibPublicSignature? {
        guard depth < 64 else { throw KlibFormatError.corruptProto("recursive IR signature") }
        switch try signature(signatureIndex, fileIndex: fileIndex) {
        case .common(let packageName, let declarationName, let memberId, let flags, _):
            return try .common(
                packageName: packageName.map { try string($0, fileIndex: fileIndex) },
                declarationName: declarationName.map { try string($0, fileIndex: fileIndex) },
                memberId: memberId, flags: flags
            )
        case .accessor(let property, let name, let hash, let flags, _):
            guard let property = try publicSignature(Int(property), fileIndex: fileIndex, depth: depth + 1) else { return nil }
            return try .accessor(property: property, name: string(name, fileIndex: fileIndex), hashId: hash, flags: flags)
        case .composite(let container, let inner):
            guard let container = try publicSignature(Int(container), fileIndex: fileIndex, depth: depth + 1),
                  let inner = try publicSignature(Int(inner), fileIndex: fileIndex, depth: depth + 1) else { return nil }
            return .composite(container: container, inner: inner)
        case .fileLocal, .scopedLocal, .local, .file:
            return nil
        }
    }

    package func string(_ index: Int32, fileIndex: Int) throws -> String {
        guard let strings else { throw KlibFormatError.corruptChunk("no strings table") }
        return try KlibStringEncoding.text(strings.element(row: fileIndex, column: Int(index)))
    }

    /// Runtime string constants must preserve isolated surrogates and escape
    /// literal internal marker characters. Names and paths use ``string``.
    package func stringLiteral(_ index: Int32, fileIndex: Int) throws -> String {
        guard let strings else { throw KlibFormatError.corruptChunk("no strings table") }
        return try KlibStringEncoding.literal(strings.element(row: fileIndex, column: Int(index)))
    }

    package func fileEntry(_ entryIndex: Int32, fileIndex: Int) throws -> KlibFileEntry {
        guard let fileEntries else { throw KlibFormatError.corruptChunk("no fileEntries table") }
        return try KlibIrDecoding.fileEntry(ProtoFields(fileEntries.element(row: fileIndex, column: Int(entryIndex))))
    }

    /// Signature debug-info string (`debugInfo.knd`), if present.
    package func signatureDebugInfo(_ index: Int32, fileIndex: Int) throws -> String? {
        guard let signatureDebugInfos, index >= 0,
              index < (try signatureDebugInfos.columnCount(row: fileIndex))
        else { return nil }
        return try KlibStringEncoding.text(signatureDebugInfos.element(row: fileIndex, column: Int(index)))
    }

    package func fqName(_ segments: [Int32], fileIndex: Int) throws -> String {
        try segments.map { try string($0, fileIndex: fileIndex) }.joined(separator: ".")
    }

    package func signatureDescription(_ signature: KlibIdSignature, fileIndex: Int) throws -> String {
        switch signature {
        case .common(let packageFqName, let declarationFqName, let memberId, _, let debugInfo):
            let package = try fqName(packageFqName, fileIndex: fileIndex)
            let declaration = try fqName(declarationFqName, fileIndex: fileIndex)
            var text = declaration
            if !package.isEmpty { text = package + "/" + text }
            if let memberId { text += "#\(memberId)" }
            if let debugInfo, let info = try signatureDebugInfo(debugInfo, fileIndex: fileIndex) {
                text += " /* \(info) */"
            }
            return text
        case .accessor(let propertySignature, let name, let hashId, _, _):
            let property = try self.signature(Int(propertySignature), fileIndex: fileIndex)
            let propertyName = try signatureDescription(property, fileIndex: fileIndex)
            return "\(propertyName).<accessor \(try string(name, fileIndex: fileIndex)):\(hashId)>"
        case .fileLocal(let container, let localId):
            let inner = try self.signature(Int(container), fileIndex: fileIndex)
            return "\(try signatureDescription(inner, fileIndex: fileIndex))!<local:\(localId)>"
        case .scopedLocal(let index):
            return "<scoped-local:\(index)>"
        case .composite(let container, let inner):
            let outer = try self.signature(Int(container), fileIndex: fileIndex)
            let innerSig = try self.signature(Int(inner), fileIndex: fileIndex)
            return "\(try signatureDescription(outer, fileIndex: fileIndex))+\(try signatureDescription(innerSig, fileIndex: fileIndex))"
        case .local(let fqNameSegments, let hash):
            var text = "<local \(try fqName(fqNameSegments, fileIndex: fileIndex))>"
            if let hash { text += "#\(hash)" }
            return text
        case .file:
            return "<file>"
        }
    }

    package func symbolDescription(_ symbol: KlibSymbolRef, fileIndex: Int) throws -> String {
        let signature = try signature(symbol.signatureIndex, fileIndex: fileIndex)
        return "\(symbol.kind):\(try signatureDescription(signature, fileIndex: fileIndex))"
    }

    package func nameAndTypeDescription(_ nameType: KlibNameAndType, fileIndex: Int) throws -> String {
        "\(try string(nameType.nameIndex, fileIndex: fileIndex)):<t\(nameType.typeIndex)>"
    }
}
