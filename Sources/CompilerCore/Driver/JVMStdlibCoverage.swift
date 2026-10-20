import Foundation

/// This report records measured ABI availability. It intentionally does not
/// promote declaration resources or frontend inline bodies to JAR coverage.
package enum JVMStdlibCoverage {
    package static func report(_ program: JVMProgram, classFiles: [(String, Data)]) throws -> Data {
        var classes: [String: JVMClassInfo] = [:]
        for (_, bytes) in classFiles {
            var reader = JVMClassReader(bytes: Array(bytes))
            let info = try reader.read(); classes[info.name] = info
        }
        func contains(_ owner: String, _ name: String, _ descriptor: String, visited: Set<String> = []) -> Bool {
            guard !visited.contains(owner), let type = classes[owner] else { return false }
            if type.methods.contains(where: { $0.name == name && $0.descriptor == descriptor }) { return true }
            let visited = visited.union([owner])
            return ([type.superclass].compactMap { $0 } + type.interfaces).contains { contains($0, name, descriptor, visited: visited) }
        }
        let rows: [[String: Any]] = program.stdlibRequirements.map { row in
            ["owner": row.owner, "name": row.name, "descriptor": row.descriptor, "source": row.source, "status": contains(row.owner, row.name, row.descriptor) ? "jar_abi_present" : "jar_abi_missing"]
        }
        let missing = rows.filter { ($0["status"] as? String) == "jar_abi_missing" }.count
        let document: [String: Any] = [
            "schemaVersion": 1, "complete": false,
            "description": "Known text/collection/sequence API declarations; ABI presence is not execution coverage.",
            "scope": "Known text/collection/sequence ABI signatures; runtime linkage and execution are checked separately.",
            "runtimeLinkageCheck": "Scripts/validate_jvm_stdlib.py",
            "abiPresent": rows.count - missing, "abiMissing": missing, "apis": rows,
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }
}
