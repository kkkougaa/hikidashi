import Foundation

/// 동기화 파일 암호화 (종단간). 웹 `src/data/vault.ts` 와 같은 형식 (docs/SPEC.md 동기화):
/// PBKDF2-SHA256(암호 NFC, salt, iter) → 256비트 키 → AES-GCM(12바이트 iv), data = 암호문 ‖ 16바이트 태그
public struct SyncKdf: Codable, Equatable, Sendable {
    public var name = "PBKDF2"
    public var hash = "SHA-256"
    public var iter: Int
    /// base64
    public var salt: String

    public init(iter: Int, salt: String) {
        self.iter = iter
        self.salt = salt
    }
}

public struct SyncEnvelope: Codable, Equatable, Sendable {
    public var app = "hikidashi-sync"
    public var v = 1
    public var kdf: SyncKdf
    /// base64
    public var iv: String
    /// base64 (암호문 ‖ 태그)
    public var data: String

    public init(kdf: SyncKdf, iv: String, data: String) {
        self.kdf = kdf
        self.iv = iv
        self.data = data
    }

    public static func decode(_ data: Data) throws -> SyncEnvelope {
        guard let e = try? JSONDecoder().decode(SyncEnvelope.self, from: data),
              e.app == "hikidashi-sync", e.v == 1, e.kdf.name == "PBKDF2", e.kdf.hash == "SHA-256" else {
            throw SyncVaultError.notSyncFile
        }
        return e
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}

public enum SyncVaultError: Error, Equatable, LocalizedError {
    /// 암호가 틀렸거나 다른 기기에서 암호를 바꿨다
    case wrongPassphrase
    case notSyncFile
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .wrongPassphrase: "동기화 암호가 맞지 않아요"
        case .notSyncFile: "hikidashi 동기화 파일이 아니에요"
        case .unsupported: "이 기기에선 암호화를 쓸 수 없어요"
        }
    }
}

/// 이 기기에 넣어 두는 키 (키체인)
public struct SyncKey: Codable, Equatable, Sendable {
    public var key: Data
    public var kdf: SyncKdf

    public init(key: Data, kdf: SyncKdf) {
        self.key = key
        self.kdf = kdf
    }
}

/// 받은 파일보다 이 기기에 더 새것이 있는지 (있으면 올린다)
public func hasNewer(folders: [Folder], items: [Item], than remote: Backup) -> Bool {
    !mergeRecords(remote.folders, folders).changed.isEmpty || !mergeRecords(remote.items, items).changed.isEmpty
}

#if canImport(CryptoKit) && canImport(CommonCrypto)
import CryptoKit
import CommonCrypto
import Security

public enum SyncVault {
    public static let defaultIterations = 600_000

    public static func newKdf(iter: Int = defaultIterations) -> SyncKdf {
        var salt = Data(count: 16)
        salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return SyncKdf(iter: iter, salt: salt.base64EncodedString())
    }

    /// 암호 → 키. 한글은 입력기마다 조합 방식이 달라서 NFC 로 맞춘다
    public static func deriveKey(passphrase: String, kdf: SyncKdf) throws -> SyncKey {
        guard let salt = Data(base64Encoded: kdf.salt) else { throw SyncVaultError.notSyncFile }
        let pass = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { s in
            pass.withUnsafeBufferPointer { p in
                p.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pass.count) { pp in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pp, pass.count,
                                         s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(kdf.iter), &out, out.count)
                }
            }
        }
        guard Int(status) == kCCSuccess else { throw SyncVaultError.unsupported }
        return SyncKey(key: Data(out), kdf: kdf)
    }

    public static func seal(_ plain: Data, with key: SyncKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key.key), nonce: nonce)
        let env = SyncEnvelope(kdf: key.kdf, iv: Data(nonce).base64EncodedString(), data: (box.ciphertext + box.tag).base64EncodedString())
        return try env.encoded()
    }

    public static func open(_ env: SyncEnvelope, with key: SyncKey) throws -> Data {
        // 다른 기기에서 암호를 바꿨으면 salt 가 다르다
        guard env.kdf.salt == key.kdf.salt, env.kdf.iter == key.kdf.iter else { throw SyncVaultError.wrongPassphrase }
        guard let iv = Data(base64Encoded: env.iv), let all = Data(base64Encoded: env.data), all.count >= 16 else { throw SyncVaultError.notSyncFile }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: all.dropLast(16), tag: all.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: key.key))
        } catch {
            throw SyncVaultError.wrongPassphrase
        }
    }
}
#endif
