//
//  SoulMemory.swift
//  模块：Features/Canvas（界面层的状态；依赖 Data 与 Oracle）
//
//  文件职责：他记得的东西在这一次运行里的那一份——读、记、压、存（计划 K 组，决策 84、86）。
//
//  · 启动时从加密文件读出（K3）；每记一轮就存回去。
//  · 原样的对话攒够了，就请模型把最旧的几轮压进「他记得的事」（K4），压完再存。
//  · 出了问题如实摆出来（`problem`，界面印在纸上）：读不出来时**不再往那个文件里写**，
//    免得拿空记忆把用户原来的记忆覆盖掉；压不出来时原样的对话留着，下一轮再压，不丢东西。
//
//  用户 2026-11-18 定：记忆默认开着，不做开关、不做遗忘按钮（先测试）。
//

import Foundation

@MainActor
@Observable
final class SoulMemory {
    /// 他记得的东西。
    private(set) var remembered: DiaryMemory
    /// 出了什么问题。nil = 好好的。界面把 `sentence` 印在纸上。
    private(set) var problem: MemoryVaultError?

    /// nil = 只在内存里（测试用），不读不写文件，也不算问题。
    private let vault: MemoryVault?
    /// 读坏了以后不再写（见文件头）。
    private var writingBlocked = false
    private var folding = false

    #if DEBUG
    /// 最近一次压记忆的结果（压了几轮、多少字，或者失败的原因）。只在 DEBUG 里，不含日记内容。
    private(set) var lastFold: String?

    /// 纸上 DEBUG 诊断行的记忆那一半：称呼、记得的事多长、原样留着几轮、上一次压的结果。
    var debugLine: String {
        "记忆：称呼\(remembered.name.map { "「\($0)」" } ?? "无")｜记得的事 \(remembered.summary?.count ?? 0) 字｜原样 \(remembered.turns.count) 轮｜\(lastFold ?? "还没压过")"
    }
    #endif

    init(vault: MemoryVault?) {
        self.vault = vault
        guard let vault else {
            remembered = DiaryMemory()
            return
        }
        do {
            remembered = try vault.load()
        } catch {
            remembered = DiaryMemory()
            problem = error as? MemoryVaultError ?? .unreadable(String(describing: type(of: error)))
            writingBlocked = true
        }
    }

    /// 生产用：加密文件 + 钥匙串。连存放的目录都拿不到时，如实报出来，这一次运行只记在内存里。
    static func onDevice() -> SoulMemory {
        do {
            return SoulMemory(vault: try MemoryVault.onDevice())
        } catch {
            let memory = SoulMemory(vault: nil)
            memory.problem = .unwritable("找不到存放记忆的目录：\(type(of: error))")
            return memory
        }
    }

    /// 记下一轮，顺便记下这一句里说出的称呼。
    func record(_ turn: OracleTurn, name: String?) {
        remembered.record(turn, name: name)
        persist()
    }

    /// 原样的对话攒够了就请模型压一次。同一时间只压一次；压的时候新来的轮次接在后面，不受影响。
    func foldIfNeeded(using oracle: OracleProvider) async {
        guard !folding, let batch = remembered.turnsToFold else { return }
        folding = true
        defer { folding = false }
        do {
            let condensed = try await oracle.condenseMemory(previous: remembered.summary, turns: batch)
            remembered.folded(batch.count, into: condensed)
            persist()
            #if DEBUG
            lastFold = "压了 \(batch.count) 轮 → \(condensed.count) 字"
            print("── 记忆（K4）── \(lastFold ?? "")")
            #endif
        } catch {
            // 原样的对话还在，下一轮会再试；不丢东西，也不编一段记忆顶上。
            #if DEBUG
            lastFold = "压记忆失败：\(error)"
            print("── 记忆（K4）── \(lastFold ?? "")")
            #endif
        }
    }

    private func persist() {
        guard let vault, !writingBlocked else { return }
        do {
            try vault.save(remembered)
        } catch {
            problem = error as? MemoryVaultError ?? .unwritable(String(describing: type(of: error)))
        }
    }
}
