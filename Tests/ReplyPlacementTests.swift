//
//  ReplyPlacementTests.swift
//  模块：Tests（回应落在哪，计划 E9e）
//
//  文件职责：验证落点决策。
//
//  为什么这一层的错误后果最直接：
//  它决定魂的字画在页面的哪个位置。答错的两种形态都很难查——
//  压在用户的字上（看起来像排版乱了），或者明明有地方却报「放不下」（看起来像功能没做）。
//
//  所以这里重点测四件事：
//  一、**绝不压字**：任何返回的落点都必须落在空处，且在页内。
//  二、位置要贴着用户写的东西（右边或下方），而不是跑到页面另一头。
//  三、放不下时**报错**而不是凑一个位置——那个错误就是「该翻页了」的信号。
//  四、同一种子必得同一结果，不同种子会换位置（用户要的「随机空位」）。
//

import Foundation
@testable import TomRiddlesDiary
import XCTest

nonisolated final class ReplyPlacementTests: XCTestCase {
    private let glyphSize = 40.0
    private let lineSpacingRatio = 1.6
    private let reply = "我看见你今天写得很慢"

    private var page: PageRegion {
        PageRegion(left: 0, top: 0, width: 800, height: 1_000)
    }

    private func makeInkMap(marking polylines: [Polyline] = []) -> PageInkMap {
        var map = PageInkMap(
            page: page,
            resolution: PageInkMap.Resolution(glyphHeight: glyphSize, lineSpacingRatio: lineSpacingRatio)
        )
        map.mark(polylines)
        return map
    }

    /// 造一段「用户写的字」：一条横向的墨迹带。
    private func makeWriting(left: Double, top: Double, width: Double, height: Double) -> [Polyline] {
        stride(from: top, through: top + height, by: 6).map { y in
            Polyline(points: [Point2D(x: left, y: y), Point2D(x: left + width, y: y)])
        }
    }

    private func place(
        after writing: PageRegion?,
        on map: PageInkMap,
        seed: UInt64 = 7,
        text: String? = nil
    ) throws -> ReplyPlacement {
        try ReplyPlacementFinder().place(
            text ?? reply,
            glyphSize: glyphSize,
            lineSpacingRatio: lineSpacingRatio,
            after: writing,
            on: map,
            seed: seed
        )
    }

    // MARK: 绝不压字

    /// 核心用例：返回的落点必须落在空处，而且在页内。
    /// 这条是整个 E9e 的底线——压字比放不下严重得多。
    func testPlacementNeverOverlapsExistingInk() throws {
        let writing = makeWriting(left: 60, top: 100, width: 300, height: 60)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        for seed in UInt64(1) ... 40 {
            let placement = try place(after: region, on: map, seed: seed)

            XCTAssertTrue(map.canPlace(placement.region), "seed \(seed) 的落点压到了已有墨迹")
            XCTAssertTrue(placement.region.isContained(in: page), "seed \(seed) 的落点跑出了页面")
            XCTAssertFalse(placement.region.intersects(region), "seed \(seed) 的落点与用户的字重叠")
        }
    }

    /// 排出来的宽度必须真的落在声明的行宽之内，否则「按这个宽度找空位」就没意义。
    func testPlacedBlockFitsTheDeclaredLineWidth() throws {
        let writing = makeWriting(left: 60, top: 100, width: 300, height: 60)
        let map = makeInkMap(marking: writing)

        let placement = try place(after: PageRegion.covering(writing), on: map)

        XCTAssertLessThanOrEqual(placement.region.width, placement.lineWidth)
        XCTAssertGreaterThan(placement.lineWidth, 0)
    }

    // MARK: 位置要贴着用户写的东西

    /// 页面很空时，落点必须落在用户那句话的右边或下方，而不是跑到别处。
    func testPlacementSitsBesideTheUsersWritingWhenThePageIsEmpty() throws {
        let writing = makeWriting(left: 60, top: 200, width: 200, height: 50)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        for seed in UInt64(1) ... 20 {
            let placement = try place(after: region, on: map, seed: seed)

            XCTAssertTrue(
                placement.slot == .rightOfWriting || placement.slot == .belowWriting,
                "seed \(seed) 落在了 \(placement.slot)，页面这么空不该用退路"
            )
        }
    }

    /// 落在右边时，它必须真的在右边（而不是名字叫右边、位置在别处）。
    func testRightSlotIsActuallyToTheRight() throws {
        let writing = makeWriting(left: 40, top: 300, width: 180, height: 50)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        var checked = false
        for seed in UInt64(1) ... 40 {
            let placement = try place(after: region, on: map, seed: seed)
            guard placement.slot == .rightOfWriting else { continue }

            XCTAssertGreaterThan(placement.origin.x, region.right, "标称在右边，实际却不在右边")
            checked = true
        }
        XCTAssertTrue(checked, "四十个种子里应该出现过「右边」这个选择")
    }

    /// 落在下方时同理。
    func testBelowSlotIsActuallyBelow() throws {
        let writing = makeWriting(left: 40, top: 300, width: 180, height: 50)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        var checked = false
        for seed in UInt64(1) ... 40 {
            let placement = try place(after: region, on: map, seed: seed)
            guard placement.slot == .belowWriting else { continue }

            XCTAssertGreaterThan(placement.origin.y, region.bottom, "标称在下方，实际却不在下方")
            checked = true
        }
        XCTAssertTrue(checked, "四十个种子里应该出现过「下方」这个选择")
    }

    /// 用户的字贴着页面右边缘时，「右边」放不下，必须自动改到下方。
    /// 这条防的是「只会往右放」——那样靠右写字就永远得不到回应。
    func testFallsBackToBelowWhenThereIsNoRoomOnTheRight() throws {
        // 从左 60 一直写到接近页面右缘，右边只剩不到一个字的宽度。
        let writing = makeWriting(left: 60, top: 200, width: 700, height: 50)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        for seed in UInt64(1) ... 20 {
            let placement = try place(after: region, on: map, seed: seed)
            XCTAssertNotEqual(placement.slot, .rightOfWriting, "右边明明放不下")
            XCTAssertTrue(map.canPlace(placement.region))
        }
    }

    /// 这一轮没有可挨着的字时（比如刚翻开一页），从可书写区域左上角写起。
    func testNoWritingToSitBesideStartsAtTheTopLeft() throws {
        let placement = try place(after: nil, on: makeInkMap())

        XCTAssertEqual(placement.slot, .startOfPage)
        XCTAssertEqual(placement.origin.x, page.left, accuracy: glyphSize)
        XCTAssertEqual(placement.origin.y, page.top, accuracy: glyphSize)
    }

    // MARK: 放不下要报错，不许凑

    /// 整页写满时必须报 `noRoomOnThisPage`——那就是「该翻页了」的信号。
    /// 凑一个位置的后果是回应压在用户的字上。
    func testFullPageThrowsInsteadOfSqueezingIn() {
        var map = makeInkMap()
        for y in stride(from: 2.0, through: 998.0, by: 8) {
            map.mark([Polyline(points: [Point2D(x: 0, y: y), Point2D(x: 800, y: y)])])
        }

        XCTAssertThrowsError(try place(after: nil, on: map)) { error in
            XCTAssertEqual(error as? ReplyPlacementFailure, .noRoomOnThisPage)
        }
    }

    /// 一个字都排不出来时，报的是「排不出来」而不是「放不下」——
    /// 两者的处置完全不同：一个要补字形数据，一个要翻页。
    func testTextThatProducesNoInkThrowsTheSpecificReason() {
        XCTAssertThrowsError(
            try place(after: nil, on: makeInkMap(), text: "αβγ")
        ) { error in
            guard case .textProducesNoInk(let missing) = error as? ReplyPlacementFailure else {
                return XCTFail("应报「排不出来」，得到的是 \(error)")
            }
            XCTAssertEqual(missing.count, 3)
        }
    }

    /// 页面窄到连最小行宽都放不下时，同样报错而不是硬排。
    func testPageNarrowerThanTheMinimumLineWidthThrows() {
        let narrow = PageRegion(left: 0, top: 0, width: glyphSize * 3, height: 400)
        var map = PageInkMap(
            page: narrow,
            resolution: PageInkMap.Resolution(glyphHeight: glyphSize, lineSpacingRatio: lineSpacingRatio)
        )
        map.mark([])

        XCTAssertThrowsError(
            try ReplyPlacementFinder().place(
                reply,
                glyphSize: glyphSize,
                lineSpacingRatio: lineSpacingRatio,
                after: nil,
                on: map,
                seed: 7
            )
        ) { error in
            XCTAssertEqual(error as? ReplyPlacementFailure, .noRoomOnThisPage)
        }
    }

    // MARK: 随机但可复现

    /// 同一种子必得同一结果，否则测试没法断言、出问题也没法重放。
    func testSameSeedGivesTheSamePlacement() throws {
        let writing = makeWriting(left: 60, top: 200, width: 200, height: 50)
        let map = makeInkMap(marking: writing)
        let region = PageRegion.covering(writing)

        let first = try place(after: region, on: map, seed: 42)
        let second = try place(after: region, on: map, seed: 42)

        XCTAssertEqual(first, second)
    }

    /// 不同种子应该会换位置——用户要的就是「随机空位」，
    /// 固定优先级会让每次回应都落在同一个相对位置上，一页写下来像表格。
    func testDifferentSeedsChooseDifferentSlots() throws {
        let writing = makeWriting(left: 60, top: 200, width: 200, height: 50)
        let map = makeInkMap(marking: writing)
        let region = PageRegion.covering(writing)

        var slots: Set<String> = []
        for seed in UInt64(1) ... 30 {
            slots.insert(String(describing: try place(after: region, on: map, seed: seed).slot))
        }

        XCTAssertGreaterThan(slots.count, 1, "三十个种子应该出现过不止一种位置")
    }

    /// 即使落在同一类位置上，具体坐标也该有一点抖动——不要每次精确贴同一个点。
    func testPlacementJittersWithinTheSameSlot() throws {
        let writing = makeWriting(left: 60, top: 200, width: 200, height: 50)
        let map = makeInkMap(marking: writing)
        let region = PageRegion.covering(writing)

        var originsBySlot: [String: Set<Double>] = [:]
        for seed in UInt64(1) ... 40 {
            let placement = try place(after: region, on: map, seed: seed)
            originsBySlot[String(describing: placement.slot), default: []].insert(placement.origin.x)
        }

        XCTAssertTrue(
            originsBySlot.values.contains { $0.count > 1 },
            "同一类位置上应该出现过不同的横坐标（抖动）"
        )
    }

    // MARK: 真实内容端到端

    /// 中英混排 + 标点走完整条路：落点算出来、排出来、不压字。
    func testMixedContentPlacesAndFitsEndToEnd() throws {
        let writing = makeWriting(left: 60, top: 120, width: 260, height: 70)
        let map = makeInkMap(marking: writing)
        let region = try XCTUnwrap(PageRegion.covering(writing))

        let placement = try place(after: region, on: map, text: "我看见你写的 hello，慢一点。")

        XCTAssertTrue(map.canPlace(placement.region))
        // 按算出来的落点真排一遍，结果必须和落点里记的占地一致。
        let laidOut = try GlyphStrokeLayout().layOut(
            "我看见你写的 hello，慢一点。",
            configuration: GlyphStrokeLayoutConfiguration(
                glyphSize: glyphSize,
                lineWidth: placement.lineWidth,
                lineSpacingRatio: lineSpacingRatio,
                origin: CGPoint(x: placement.origin.x, y: placement.origin.y)
            )
        )
        XCTAssertEqual(laidOut.boundingBox, placement.region, "真排出来的位置必须和落点算的一致")
    }
}
