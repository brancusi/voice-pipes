// Makes the EdDSA (ed25519) key pair that signs Voice Tools updates. Run once, ever:
//   swiftc Tools/make_update_key.swift -o "$TMPDIR/make_update_key" && "$TMPDIR/make_update_key" ~/voice-tools-update-key.txt
// Writes the PRIVATE key (base64 seed, the format Sparkle's sign_update --ed-key-file reads) to the given file,
// readable only by you, and refuses to overwrite one. Prints the PUBLIC key for build.sh (UPDATE_PUBLIC_KEY).
// Keep the private key in your password manager and in the GitHub secret; if it's lost, installed copies can't
// take updates any more and everyone has to reinstall by hand once.
//   make_update_key --public < private-key-file   # prints a private key's public half (CI checks it matches)
import CryptoKit
import Foundation

if CommandLine.arguments.dropFirst() == ["--public"] {
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
        FileHandle.standardError.write("not a base64 ed25519 private key\n".data(using: .utf8)!)
        exit(1)
    }
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: make_update_key <private-key-file>\n".data(using: .utf8)!)
    exit(2)
}
let path = CommandLine.arguments[1]
let key = Curve25519.Signing.PrivateKey()
let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
guard fd >= 0 else {
    FileHandle.standardError.write("\(path): \(String(cString: strerror(errno))) (never overwritten)\n".data(using: .utf8)!)
    exit(1)
}
let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
handle.write((key.rawRepresentation.base64EncodedString() + "\n").data(using: .utf8)!)
try handle.synchronize()
print(key.publicKey.rawRepresentation.base64EncodedString())
