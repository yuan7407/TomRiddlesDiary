//
//  GlyphStrokeProvider.swift
//  模块：Handwriting（纯逻辑层，与 StrokeEngine 平级；不依赖 UI、网络或模型）
//
//  文件职责：查出一个字该怎么写——每一笔从哪走到哪、按什么顺序。
//
//  这是整个产品缺了最久的那块拼图。模型只会返回字符（「累」就是一个码点 U+7D2F，
//  里面没有任何「先写哪一笔」的信息），而普通字体存的是字的**外框轮廓**不是笔迹。
//  要一笔一笔写出来，只能靠一份带笔顺的**中线**数据。这个文件就是它的入口。
//
//  数据来源与授权：
//  makemeahanzi 项目的 graphics.txt，其中的 medians 字段即每笔的中线点序列。
//  该数据派生自文鼎科技 1999 年以 Arphic Public License 公开的两套楷体
//  （Arphic PL KaitiM GB 与 Arphic PL UKai）。授权要求随数据附上授权副本，
//  因此 `ARPHICPL.TXT` 与上游的 `COPYING` 一并打进了 App 资源。
//  1999 版允许商用；文鼎 2010 年的修订版限定非营利，本项目用的是 1999 版。
//
//  设计原因：
//  - **只提取 medians，丢掉 strokes（轮廓路径）**。原始 graphics.txt 有 30.78 MB，
//    其中大部分是轮廓；只留中线并扁平化后是 5.26 MB。轮廓对我们毫无用处——
//    我们要的是「笔怎么走」，不是「墨的边界在哪」。
//  - **不自建二进制格式**。int16 二进制能压到 2.76 MB，但要自己维护格式与生成脚本。
//    5.26 MB 相对已打包的 3.9 MB 字体不算多，JSON 可读可查，一次性后台解析即可。
//  - **一次性整体解析并缓存**，而不是每个字读一个文件。9574 个小文件在 App 包里
//    按块对齐会占掉远超 5 MB 的磁盘，而整体解析只发生一次。
//  - 输出**归一化坐标**（0…1，y 向下）而不是页面点：这一层不该知道字写多大，
//    缩放和定位是排版层的事。
//
//  坐标系换算（实测反证过，不是照抄文档）：
//  原始数据是 1024 em 方格、**y 轴朝上**（字体惯例）。反证方法：「上」字的长横
//  视觉上在最下方，其 y 值是全字最小（72…132）；「下」字的横视觉上在最上方，
//  其 y 值是全字最大（664…745）。因此 y 越大越靠上，需要翻转。
//  em 方格顶部对应 y = 900（观测到的全局 y 范围是 -96…885，落在 [-124, 900] 内）。
//  故 归一化y = (900 - y) / 1024，归一化x = x / 1024。
//

import Foundation

/// 一个字的书写方式：按笔顺排列的中线，坐标已归一化到 0…1 的字面方格，y 向下。
nonisolated struct GlyphStrokes: Equatable, Sendable {
    /// 这个字的字符。
    let character: Character

    /// 按笔顺排列的每一笔。坐标在 0…1 的字面方格内，原点左上、y 向下。
    /// 允许略微越界：部分字的笔画会伸出字面方格一点，这是字体设计的常态。
    let strokes: [Polyline]
}

/// 查不到字形时的原因。刻意区分两种情况，不合并成一个「查不到」：
/// 调用方对它们的处理不同——缺笔顺数据的字（标点、拉丁字母）是**已知缺口**，
/// 而资源本身加载失败是**故障**。
nonisolated enum GlyphStrokeLookupFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// 字形数据资源没打进包，或者格式不对。这是故障。
    case resourceUnavailable(String)

    /// 资源正常，但这个字不在数据集里。这是已知缺口：
    /// 数据集只覆盖汉字，标点、拉丁字母、数字都不在其中。
    case characterNotCovered(Character)

    var description: String {
        switch self {
        case .resourceUnavailable(let reason):
            "字形笔顺数据不可用：\(reason)"
        case .characterNotCovered(let character):
            "字形笔顺数据里没有「\(character)」（数据集只覆盖汉字，不含标点与拉丁字母）"
        }
    }
}

/// 字形笔顺查询。
nonisolated struct GlyphStrokeProvider: Sendable {
    /// 原始数据的字面方格边长（em 单位）。
    static let designUnitsPerEm: Double = 1024

    /// 字面方格顶部对应的原始 y 值。见文件头的坐标系说明。
    static let designTopY: Double = 900

    private static let resourceName = "hanzi-medians"
    private static let resourceExtension = "json"

    /// 数据来源署名，分发时必须可见。
    static let attribution = "字形笔顺数据来自 makemeahanzi，派生自文鼎科技 1999 年公开授权的楷体"

    /// 覆盖的字数，供诊断与文档核对。
    static var coveredCharacterCount: Int {
        (try? loadedTable().count) ?? 0
    }

    /// 查一个字怎么写。
    /// - Throws: `GlyphStrokeLookupFailure`。**不返回 nil 兜底**：
    ///   「这个字没有笔顺数据」必须让调用方明确处理，否则页面上会凭空少一个字。
    func strokes(for character: Character) throws -> GlyphStrokes {
        let table = try Self.loadedTable()
        guard let flattened = table[String(character)] else {
            throw GlyphStrokeLookupFailure.characterNotCovered(character)
        }

        let strokes = flattened.compactMap { flat -> Polyline? in
            // 扁平数组是 [x,y,x,y,...]，奇数长度说明数据损坏，跳过而不是崩掉——
            // 单个字损坏不该让整页写不出来。
            guard flat.count >= 2, flat.count.isMultiple(of: 2) else { return nil }
            var points: [Point2D] = []
            points.reserveCapacity(flat.count / 2)
            for index in stride(from: 0, to: flat.count, by: 2) {
                points.append(Self.normalized(x: Double(flat[index]), y: Double(flat[index + 1])))
            }
            return Polyline(points: points)
        }

        return GlyphStrokes(character: character, strokes: strokes)
    }

    /// 这个字有没有笔顺数据。用于排版前先分辨哪些字画得出来。
    func covers(_ character: Character) -> Bool {
        guard let table = try? Self.loadedTable() else { return false }
        return table[String(character)] != nil
    }

    /// 原始 em 坐标 → 归一化字面方格坐标（0…1，y 向下）。
    static func normalized(x: Double, y: Double) -> Point2D {
        Point2D(
            x: x / designUnitsPerEm,
            y: (designTopY - y) / designUnitsPerEm
        )
    }

    // MARK: 资源加载

    /// 整份数据只解析一次。用 `Result` 缓存而不是可选值：
    /// 加载失败的原因必须保留，否则第二次调用只会得到一个没有解释的空表。
    private static let table: Result<[String: [[Int]]], GlyphStrokeLookupFailure> = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            return .failure(.resourceUnavailable("App 包里找不到 \(resourceName).\(resourceExtension)"))
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let decoded = try JSONDecoder().decode([String: [[Int]]].self, from: data)
            return .success(decoded)
        } catch {
            return .failure(.resourceUnavailable(String(describing: error)))
        }
    }()

    private static func loadedTable() throws -> [String: [[Int]]] {
        try table.get()
    }
}
