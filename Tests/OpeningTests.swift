//
//  OpeningTests.swift
//  测试目标：计划 P6「他先开口」——Persona.json 的开场白、模型的 openBook。
//
//  为什么这样测：开场白是他的话，放在人设文件里，写漏一组钟点不会报错，只会某个时段不开场；
//  开场的位置照原型（他在左页、和右页 0.25 纸高齐平，线在右页），写反了就是两页互换。
//  坐标用 Duo 内屏实测值：951 × 669，折缝 x 455.5、宽 40，安全区右 84、下 34。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class OpeningTests: XCTestCase {
    private func bundledOpening() throws -> SoulPersona.Opening {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let persona = try SoulPersonaLoader.decode(Data(contentsOf: root.appendingPathComponent("Sources/Resources/Persona.json")))
        return try XCTUnwrap(persona.opening, "Persona.json 里没有 opening")
    }

    /// 一天的每个钟点都要有一句，不许有开不了场的时段。
    func testEveryHourHasAGreeting() throws {
        let opening = try bundledOpening()
        for hour in 0 ..< 24 {
            XCTAssertNotNil(opening.lines(hour: hour, name: nil), "\(hour) 点开不了场")
        }
    }

    func testFirstVisitAsksYourNameAndReturningSaysWelcomeBack() throws {
        let opening = try bundledOpening()
        XCTAssertEqual(opening.lines(hour: 14, name: nil), "你来了。\n怎么称呼你？")
        XCTAssertEqual(opening.lines(hour: 14, name: "Michael"), "你回来了，Michael。\n想写点什么？")
        XCTAssertEqual(opening.lines(hour: 2, name: nil), "这么晚了，还醒着。\n怎么称呼你？")
    }

    @MainActor
    func testOpeningIsWrittenOnTheLeftWithALineOnTheRight() async throws {
        let spread = SpreadGeometry(
            bounds: PageRegion(left: 0, top: 0, width: 951, height: 669),
            fold: PageRegion(left: 455.5, top: 0, width: 40, height: 669)
        )
        let model = DiaryPageModel(oracle: nil, composer: .forSoul())
        model.pageAreaChanged(PageRegion(left: 53.5, top: 53.5, width: 760, height: 528))
        model.foldChanged(spread.fold)
        model.facingColumnsChanged(ReplyComposer.facingColumns(spread: spread, safeTop: 0, safeBottom: 34, safeTrailing: 84))

        await model.openBook(lines: "你来了。\n怎么称呼你？", spreadHeight: 669)

        let reply = try XCTUnwrap(model.reply, "没有开场")
        XCTAssertTrue(model.greetingOnPage)
        let line = try XCTUnwrap(reply.sequence.polylines.last)
        XCTAssertTrue(line.points.allSatisfy { $0.x > 495.5 }, "那道线应该在右页")
        let words = PageRegion.covering(Array(reply.sequence.polylines.dropLast()))
        XCTAssertLessThan(try XCTUnwrap(words).right, 455.5, "他的话应该在左页")
        XCTAssertNotNil(model.openingHintPoint)

        // 一次启动只开一次场。
        await model.openBook(lines: "又一次", spreadHeight: 669)
        XCTAssertEqual(model.reply?.sequence, reply.sequence)
    }
}
