//
//  MemoryVault.swift
//  模块：Data（Foundation + CryptoKit + Security）
//
//  文件职责：把他记得的东西（`DiaryMemory`）加密存在手机上，跨启动保留（计划 K3，AGENTS「日记默认端侧加密」）。
//
//  怎么加密：AES-GCM（CryptoKit），256 位钥匙放在钥匙串里（只在这台设备、首次解锁后可读，不随备份迁走）。
//  文件写在 App 的 Application Support 目录，再加上系统的文件保护（锁屏时读不了）。
//
//  出错时不兜底（用户 2026-11-18 要求「把问题暴露出来」）：
//  · 文件不存在 = 第一次用，这不是错，返回空的记忆；
//  · 文件在、却读不出来（钥匙丢了、文件坏了、格式变了）= 错，原样抛出去，由调用方显示出来，
//    **而且调用方不能拿空记忆把那个文件覆盖掉**——那等于悄悄删了用户的东西。
//

import CryptoKit
import Foundation
import Security

/// 存放那把钥匙的地方。生产用钥匙串；测试用内存里的一把，不碰钥匙串。
nonisolated protocol MemoryKeyStore: Sendable {
    /// 取钥匙；还没有时返回 nil。
    func loadKey() throws -> SymmetricKey?
    func saveKey(_ key: SymmetricKey) throws
}

nonisolated enum MemoryVaultError: Error, Equatable, Sendable {
    /// 文件在，但钥匙串里没有钥匙：文件解不开。
    case keyMissing
    /// 钥匙串报错（带系统错误码）。
    case keychain(OSStatus)
    /// 解密失败：钥匙不对或文件被改过、坏了。
    case unreadable(String)
    /// 写不进去。
    case unwritable(String)

    /// 显示在纸上的那句话（印刷体，系统说的）。不含任何日记内容。
    var sentence: String {
        switch self {
        case .keyMissing: "他的记忆打不开了：钥匙串里找不到钥匙。旧的记忆没有被删，也不会被覆盖。"
        case .keychain(let status): "他的记忆打不开了：钥匙串出错（\(status)）。旧的记忆没有被删，也不会被覆盖。"
        case .unreadable(let detail): "他的记忆读不出来了（\(detail)）。旧的记忆没有被删，也不会被覆盖。"
        case .unwritable(let detail): "这一轮没能记下来（\(detail)）。"
        }
    }
}

nonisolated struct MemoryVault: Sendable {
    let fileURL: URL
    let keys: MemoryKeyStore

    /// 生产用：Application Support 下的文件 + 钥匙串。
    static func onDevice() throws -> MemoryVault {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        return MemoryVault(fileURL: folder.appendingPathComponent(InteractionSettings.Memory.fileName),
                           keys: KeychainMemoryKeyStore())
    }

    /// 读出来。文件不存在返回空记忆；文件在却读不出来就抛错（见文件头）。
    func load() throws -> DiaryMemory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DiaryMemory() }
        guard let key = try keys.loadKey() else { throw MemoryVaultError.keyMissing }
        do {
            let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: fileURL))
            let plain = try AES.GCM.open(sealed, using: key)
            return try JSONDecoder().decode(DiaryMemory.self, from: plain)
        } catch {
            throw MemoryVaultError.unreadable(String(describing: type(of: error)))
        }
    }

    /// 写进去：没有钥匙就先造一把存进钥匙串。
    func save(_ memory: DiaryMemory) throws {
        let key: SymmetricKey
        if let existing = try keys.loadKey() {
            key = existing
        } else {
            key = SymmetricKey(size: .bits256)
            try keys.saveKey(key)
        }
        do {
            let plain = try JSONEncoder().encode(memory)
            guard let combined = try AES.GCM.seal(plain, using: key).combined else {
                throw MemoryVaultError.unwritable("加密结果为空")
            }
            try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch let error as MemoryVaultError {
            throw error
        } catch {
            throw MemoryVaultError.unwritable(String(describing: type(of: error)))
        }
    }
}

/// 钥匙串里的那把钥匙。只在这台设备、首次解锁后可读，不随 iCloud 或备份迁到别的设备。
nonisolated struct KeychainMemoryKeyStore: MemoryKeyStore {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: InteractionSettings.Memory.keychainService,
            kSecAttrAccount as String: InteractionSettings.Memory.keychainAccount,
        ]
    }

    func loadKey() throws -> SymmetricKey? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw MemoryVaultError.keychain(status) }
        return SymmetricKey(data: data)
    }

    func saveKey(_ key: SymmetricKey) throws {
        var item = query
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw MemoryVaultError.keychain(status) }
    }
}
