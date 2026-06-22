
// MARK: - Core geometry

/// A 0-based position in a text document. `character` counts UTF-16 code units.
struct LSPPosition: Codable, Equatable {
    var line: Int
    var character: Int

    init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

struct LSPRange: Codable, Equatable {
    var start: LSPPosition
    var end: LSPPosition

    init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

struct LSPLocation: Codable, Equatable {
    var uri: String
    var range: LSPRange

    init(uri: String, range: LSPRange) {
        self.uri = uri
        self.range = range
    }
}

// MARK: - Text document identifiers

struct TextDocumentIdentifier: Codable {
    var uri: String
}

struct VersionedTextDocumentIdentifier: Codable {
    var uri: String
    var version: Int?
}

struct TextDocumentItem: Codable {
    var uri: String
    var languageId: String?
    var version: Int?
    var text: String
}

struct TextDocumentPositionParams: Codable {
    var textDocument: TextDocumentIdentifier
    var position: LSPPosition
}

// MARK: - Synchronization params

struct DidOpenTextDocumentParams: Codable {
    var textDocument: TextDocumentItem
}

/// A single content change. With full document sync (the mode this server
/// advertises) `text` carries the entire new document and `range` is absent.
struct TextDocumentContentChangeEvent: Codable {
    var text: String
}

struct DidChangeTextDocumentParams: Codable {
    var textDocument: VersionedTextDocumentIdentifier
    var contentChanges: [TextDocumentContentChangeEvent]
}

struct DidCloseTextDocumentParams: Codable {
    var textDocument: TextDocumentIdentifier
}

struct DidSaveTextDocumentParams: Codable {
    var textDocument: TextDocumentIdentifier
    var text: String?
}

struct DocumentSymbolParams: Codable {
    var textDocument: TextDocumentIdentifier
}

// MARK: - Diagnostics

/// LSP diagnostic severity codes.
enum LSPDiagnosticSeverity: Int {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

struct LSPDiagnostic: Codable, Equatable {
    var range: LSPRange
    var severity: Int?
    var code: String?
    var source: String?
    var message: String

    init(
        range: LSPRange,
        severity: Int?,
        code: String?,
        source: String?,
        message: String
    ) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
    }
}

struct PublishDiagnosticsParams: Codable {
    var uri: String
    var version: Int?
    var diagnostics: [LSPDiagnostic]

    init(uri: String, version: Int?, diagnostics: [LSPDiagnostic]) {
        self.uri = uri
        self.version = version
        self.diagnostics = diagnostics
    }
}

// MARK: - Hover

struct MarkupContent: Codable {
    /// `"markdown"` or `"plaintext"`.
    var kind: String
    var value: String

    init(kind: String = "markdown", value: String) {
        self.kind = kind
        self.value = value
    }
}

struct Hover: Codable {
    var contents: MarkupContent
    var range: LSPRange?

    init(contents: MarkupContent, range: LSPRange?) {
        self.contents = contents
        self.range = range
    }
}

// MARK: - Document symbols

/// LSP `SymbolKind` numeric codes.
enum LSPSymbolKind: Int {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case number = 16
    case boolean = 17
    case array = 18
    case object = 19
    case key = 20
    case null = 21
    case enumMember = 22
    case `struct` = 23
    case event = 24
    case `operator` = 25
    case typeParameter = 26
}

struct DocumentSymbol: Codable {
    var name: String
    var detail: String?
    var kind: Int
    var range: LSPRange
    var selectionRange: LSPRange
    var children: [DocumentSymbol]?

    init(
        name: String,
        detail: String?,
        kind: Int,
        range: LSPRange,
        selectionRange: LSPRange,
        children: [DocumentSymbol]?
    ) {
        self.name = name
        self.detail = detail
        self.kind = kind
        self.range = range
        self.selectionRange = selectionRange
        self.children = children
    }
}

// MARK: - Lifecycle

struct ServerInfo: Codable {
    var name: String
    var version: String?
}

struct ServerCapabilities: Codable {
    /// Text document sync kind: 0 = none, 1 = full, 2 = incremental.
    var textDocumentSync: Int
    var hoverProvider: Bool
    var definitionProvider: Bool
    var documentSymbolProvider: Bool
}

struct InitializeResult: Codable {
    var capabilities: ServerCapabilities
    var serverInfo: ServerInfo?
}
