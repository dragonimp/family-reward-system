import Foundation
import CryptoKit

actor HashCounter {
    var calls = 0
    func digest(_ url: URL) async throws -> String {
        calls += 1
        return try await OriginalFileVerifier.digest(url)
    }
}

@main struct OriginalFileVerifierTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("original-verifier-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("original.mov")
        try Data("abc".utf8).write(to: path)
        let sha = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let counter = HashCounter()
        let hash: @Sendable (URL) async throws -> String = { try await counter.digest($0) }
        let verifier = OriginalFileVerifier(directory: root)
        async let one = verifier.verify(path, length: 3, sha256: sha, hash: hash)
        async let two = verifier.verify(path, length: 3, sha256: sha, hash: hash)
        let both = await (one, two)
        precondition(both.0 && both.1)
        let initialCalls = await counter.calls; precondition(initialCalls == 1)
        let reopened = OriginalFileVerifier(directory: root)
        let valid = await reopened.verify(path, length: 3, sha256: sha.uppercased(), hash: hash)
        let repeatCalls = await counter.calls
        precondition(valid && repeatCalls == 1, "relaunch should not hash unchanged bytes")
        let modified = try path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        try Data("xyz".utf8).write(to: path)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path.path)
        let changed = await reopened.verify(path, length: 3, sha256: sha, hash: hash)
        let changedCalls = await counter.calls
        precondition(!changed && changedCalls == 2, "same-size edits with restored mtime must fail")
        try Data("abc".utf8).write(to: path, options: .atomic)
        let replaced = await reopened.verify(path, length: 3, sha256: sha, hash: hash)
        let replacedCalls = await counter.calls
        precondition(replaced && replacedCalls == 3)
        let linked = root.appendingPathComponent("linked.mov")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: path)
        let link = await reopened.verify(linked, length: 3, sha256: sha, hash: hash)
        precondition(!link)
        let wrongSize = await reopened.verify(path, length: 4, sha256: sha, hash: hash)
        let wrongRevision = await reopened.verify(path, length: 3, sha256: String(repeating: "0", count: 64), hash: hash)
        precondition(!wrongSize && !wrongRevision)
        try FileManager.default.removeItem(at: path)
        let missing = await reopened.verify(path, length: 3, sha256: sha, hash: hash)
        precondition(!missing)
        print("PASS: concurrent opens hash once; persisted receipt survives relaunch with zero extra hashes; same-size/mtime-restored edits and replacements rechecked; symlinks, wrong size/revision and missing files rejected")
    }
}
