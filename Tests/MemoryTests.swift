//
//  MemoryTests.swift
//  测试目标：他记得的东西（计划 K 组，决策 84、86）——怎么记、什么时候压、怎么加密存、出错时怎么办。
//
//  为什么测这些：记忆出错的后果是用户看不见的（他悄悄忘了、或者悄悄覆盖了旧记忆），所以每条规则都要机器守着：
//  · 称呼太长不收（多半是模型把整句当成了称呼）；
//  · 攒够「保留 + 一批」才压，压掉的正好是最旧的那一批，压的时候新来的不受影响；
//  · 压不出来时原样的对话不丢；
//  · 存下来的文件是密文；钥匙不对、文件坏了要报错，**而且不拿空记忆覆盖那个文件**。
//

import CryptoKit
import XCTest
@testable import TomRiddlesDiary

nonisolated final class MemoryTests: XCTestCase {
    private func turn(_ k: Int) -> OracleTurn { OracleTurn(you: "第\(k)句", him: "回\(k)") }

    // MARK: DiaryMemory

    func testNameIsKeptButOverlongNamesAreRefused() {
        var memory = DiaryMemory()
        memory.record(turn(1), name: "  Harry ")
        XCTAssertEqual(memory.name, "Harry")
        memory.record(turn(2), name: String(repeating: "长", count: InteractionSettings.Memory.nameMaxCharacters + 1))
        XCTAssertEqual(memory.name, "Harry", "太长的不是称呼")
        memory.record(turn(3), name: nil)
        XCTAssertEqual(memory.name, "Harry", "这一句没说称呼，不清掉原来的")
    }

    func testFoldsTheOldestBatchOnlyWhenEnoughHavePiledUp() {
        let m = InteractionSettings.Memory.self
        var memory = DiaryMemory()
        for k in 0 ..< m.verbatimTurns + m.foldBatch - 1 { memory.record(turn(k), name: nil) }
        XCTAssertNil(memory.turnsToFold)
        memory.record(turn(99), name: nil)
        XCTAssertEqual(memory.turnsToFold, (0 ..< m.foldBatch).map(turn))
        memory.folded(m.foldBatch, into: "他说了很多句。")
        XCTAssertEqual(memory.summary, "他说了很多句。")
        XCTAssertEqual(memory.turns.count, m.verbatimTurns)
        XCTAssertEqual(memory.turns.last, turn(99))
    }

    // MARK: MemoryVault

    private final class KeyBox: MemoryKeyStore, @unchecked Sendable {
        var key: SymmetricKey?
        init(_ key: SymmetricKey? = nil) { self.key = key }
        func loadKey() throws -> SymmetricKey? { key }
        func saveKey(_ key: SymmetricKey) throws { self.key = key }
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString).sealed")
    }

    func testRoundTripIsEncrypted() throws {
        let vault = MemoryVault(fileURL: tempFile(), keys: KeyBox())
        XCTAssertEqual(try vault.load(), DiaryMemory(), "没有文件 = 第一次用，不是错")
        var memory = DiaryMemory()
        memory.record(OracleTurn(you: "我叫 Harry", him: "Harry。"), name: "Harry")
        try vault.save(memory)
        XCTAssertEqual(try vault.load(), memory)
        let raw = try Data(contentsOf: vault.fileURL)
        XCTAssertNil(raw.range(of: Data("Harry".utf8)), "文件里不该有明文")
    }

    func testWrongKeyMissingKeyAndCorruptFileAreErrors() throws {
        let url = tempFile()
        try MemoryVault(fileURL: url, keys: KeyBox()).save(DiaryMemory())
        XCTAssertThrowsError(try MemoryVault(fileURL: url, keys: KeyBox()).load()) {
            XCTAssertEqual($0 as? MemoryVaultError, .keyMissing)
        }
        XCTAssertThrowsError(try MemoryVault(fileURL: url, keys: KeyBox(SymmetricKey(size: .bits256))).load()) {
            guard case .unreadable = $0 as? MemoryVaultError else { return XCTFail("应报读不出来：\($0)") }
        }
        try Data("坏了".utf8).write(to: url)
        XCTAssertThrowsError(try MemoryVault(fileURL: url, keys: KeyBox(SymmetricKey(size: .bits256))).load())
    }

    // MARK: SoulMemory

    private struct Condenser: OracleProvider {
        let result: Result<String, OracleFailure>
        func respond(to request: OracleRequest) async throws -> OracleReply { OracleReply(text: "") }
        func condenseMemory(previous: String?, turns: [OracleTurn]) async throws -> String { try result.get() }
    }

    @MainActor
    func testFoldingWritesTheSummaryAndFailureLosesNothing() async throws {
        let m = InteractionSettings.Memory.self
        let memory = SoulMemory(vault: MemoryVault(fileURL: tempFile(), keys: KeyBox()))
        for k in 0 ..< m.verbatimTurns + m.foldBatch { memory.record(turn(k), name: nil) }

        await memory.foldIfNeeded(using: Condenser(result: .failure(.couldNotReach(detail: "断网"))))
        XCTAssertEqual(memory.remembered.turns.count, m.verbatimTurns + m.foldBatch, "压不出来时一轮都不能丢")
        XCTAssertNil(memory.remembered.summary)

        await memory.foldIfNeeded(using: Condenser(result: .success("他写了十句。")))
        XCTAssertEqual(memory.remembered.summary, "他写了十句。")
        XCTAssertEqual(memory.remembered.turns.count, m.verbatimTurns)
    }

    /// 读不出来时：如实报出问题，并且之后记下的东西不写进那个文件（不覆盖用户原来的记忆）。
    @MainActor
    func testUnreadableMemoryIsReportedAndNeverOverwritten() throws {
        let url = tempFile()
        try Data("别人的旧记忆，坏了".utf8).write(to: url)
        let memory = SoulMemory(vault: MemoryVault(fileURL: url, keys: KeyBox(SymmetricKey(size: .bits256))))
        XCTAssertNotNil(memory.problem)
        memory.record(turn(1), name: "Harry")
        XCTAssertEqual(try Data(contentsOf: url), Data("别人的旧记忆，坏了".utf8), "坏掉的记忆文件不能被覆盖")
    }

    /// 存下来的东西跨「启动」还在：新开一个 SoulMemory 读同一个文件。
    @MainActor
    func testMemorySurvivesARelaunch() {
        let url = tempFile(), keys = KeyBox()
        SoulMemory(vault: MemoryVault(fileURL: url, keys: keys)).record(turn(1), name: "Harry")
        let again = SoulMemory(vault: MemoryVault(fileURL: url, keys: keys))
        XCTAssertNil(again.problem)
        XCTAssertEqual(again.remembered.name, "Harry")
        XCTAssertEqual(again.remembered.turns, [turn(1)])
    }

    // MARK: 称呼那一行

    func testNameLineIsParsed() {
        XCTAssertEqual(ReadingReply.parse("读到：Harry\n语气：静\n回应：Harry。你来做什么？\n关照：否\n称呼：Harry").name, "Harry")
        XCTAssertNil(ReadingReply.parse("读到：hi\n语气：静\n回应：Hi.\n关照：否\n称呼：无").name)
        XCTAssertNil(ReadingReply.parse("读到：hi\n语气：静\n回应：Hi.\n关照：否").name, "老格式没有这一行也照样能读")
    }
}
