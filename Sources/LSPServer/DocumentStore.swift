import Foundation

/// Conversion helpers between LSP document URIs and filesystem paths.
enum DocumentURI {
    /// Returns the filesystem path for a `file://` URI, or `nil` for other
    /// schemes.
    static func path(fromURI uri: String) -> String? {
        if let url = URL(string: uri), url.isFileURL {
            return url.path
        }
        if uri.hasPrefix("file://") {
            let raw = String(uri.dropFirst("file://".count))
            return raw.removingPercentEncoding ?? raw
        }
        return nil
    }

    /// Returns a `file://` URI for a filesystem path.
    static func uri(fromPath path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }
}

/// In-memory store of the documents currently open in the editor.
final class DocumentStore {
    struct Document {
        var uri: String
        var languageId: String?
        var version: Int?
        var text: String
    }

    private var documents: [String: Document] = [:]

    init() {}

    func open(uri: String, languageId: String?, version: Int?, text: String) {
        documents[uri] = Document(uri: uri, languageId: languageId, version: version, text: text)
    }

    func update(uri: String, version: Int?, text: String) {
        if var existing = documents[uri] {
            existing.version = version
            existing.text = text
            documents[uri] = existing
        } else {
            documents[uri] = Document(uri: uri, languageId: nil, version: version, text: text)
        }
    }

    func close(uri: String) {
        documents.removeValue(forKey: uri)
    }

    func text(for uri: String) -> String? {
        documents[uri]?.text
    }

    func version(for uri: String) -> Int? {
        documents[uri]?.version
    }
}
