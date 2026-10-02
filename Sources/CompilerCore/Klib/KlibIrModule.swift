import Foundation

/// Serialized-IR view of a `.klib` container: the `ir/*.kn*` chunk tables
/// bound together with per-file decoding and index resolution.
///
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
    /// `<component>/ir` entry names → table files.
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
    }

    package var hasIR: Bool { files != nil }

    package var fileCount: Int { files?.count ?? 0 }

    // MARK: - Per-file decoded entities

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

    package func type(_ typeIndex: Int32, fileIndex: Int) throws -> KlibIrType {
        guard let types else { throw KlibFormatError.corruptChunk("no types table") }
        return try KlibIrDecoding.type(ProtoFields(types.element(row: fileIndex, column: Int(typeIndex))))
    }

    package func signature(_ signatureIndex: Int, fileIndex: Int) throws -> KlibIdSignature {
        guard let signatures else { throw KlibFormatError.corruptChunk("no signatures table") }
        return try KlibIrDecoding.idSignature(ProtoFields(signatures.element(row: fileIndex, column: signatureIndex)))
    }

    /// Raw string-table bytes → UTF-8 string.
    package func string(_ index: Int32, fileIndex: Int) throws -> String {
        guard let strings else { throw KlibFormatError.corruptChunk("no strings table") }
        return String(decoding: try strings.element(row: fileIndex, column: Int(index)), as: UTF8.self)
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
        return String(decoding: try signatureDebugInfos.element(row: fileIndex, column: Int(index)), as: UTF8.self)
    }

    // MARK: - Index resolution helpers

    /// Fq-name segment list → dotted string.
    package func fqName(_ segments: [Int32], fileIndex: Int) throws -> String {
        try segments.map { try string($0, fileIndex: fileIndex) }.joined(separator: ".")
    }

    /// Resolves an `IdSignature` to a readable `pkg/Class.member`-style
    /// name (indices resolved through the file's tables).
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

    /// Resolves a symbol code to its signature description.
    package func symbolDescription(_ symbol: KlibSymbolRef, fileIndex: Int) throws -> String {
        let signature = try signature(symbol.signatureIndex, fileIndex: fileIndex)
        return "\(symbol.kind):\(try signatureDescription(signature, fileIndex: fileIndex))"
    }

    /// `name_type` pair → `(name, type)` rendered for diagnostics.
    package func nameAndTypeDescription(_ nameType: KlibNameAndType, fileIndex: Int) throws -> String {
        "\(try string(nameType.nameIndex, fileIndex: fileIndex)):<t\(nameType.typeIndex)>"
    }
}
