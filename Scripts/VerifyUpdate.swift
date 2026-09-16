import Foundation
import CryptoKit

final class Feed: NSObject, XMLParserDelegate {
    var signature: String?
    var length: Int?
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure", signature == nil {
            signature = attributes["sparkle:edSignature"]
            length = attributes["length"].flatMap(Int.init)
        }
    }
}
let args = CommandLine.arguments
let infoData = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let feed = Feed()
let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: args[2])))
parser.delegate = feed
precondition(parser.parse(), "Invalid appcast XML")
let archive = try Data(contentsOf: URL(fileURLWithPath: args[3]))
let signature = Data(base64Encoded: feed.signature ?? "")!
precondition(archive.count == feed.length, "Archive length mismatch")
precondition(publicKey.isValidSignature(signature, for: archive), "Update signature does not match app verification key")
var damaged = archive; damaged.append(0)
precondition(!publicKey.isValidSignature(signature, for: damaged), "Tampered archive incorrectly accepted")
print("PASS: Real update archive signature verified with embedded public key")
print("PASS: Tampered update archive rejected")
