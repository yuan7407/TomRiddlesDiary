//
//  HandwritingFeelTests.swift
//  模块：Tests（单位契约）
//
//  文件职责：验证计划 D1 建立的尺度契约真的成立。
//
//  设计原因：
//  D1 的全部价值就在一条不变量上——**换字号时，尺度相关的参数按比例跟着变，
//  无量纲的参数一动不动**。这条不成立，就会重新出现历史上那种「把内容硬缩放
//  去迁就参数」的补丁（当时是给夹具坐标硬除以 5）。这类回归靠肉眼看不出来，
//  必须由测试守住。
//
//  这里刻意断言比例关系而不是断言具体数值：具体数值会在计划 A10 用真人笔迹
//  重新校准，那时本文件不该失败。
//

@testable import TomRiddlesDiary
import XCTest

final class HandwritingFeelTests: XCTestCase {
    /// 字高翻倍，三个尺度相关参数必须同步翻倍。
    func testScaleDependentParametersScaleLinearly() {
        let single = HandwritingFeel.humanizerConfiguration(referenceScale: 40)
        let double = HandwritingFeel.humanizerConfiguration(referenceScale: 80)

        XCTAssertEqual(double.sampleSpacing, single.sampleSpacing * 2, accuracy: 1e-12)
        XCTAssertEqual(double.jitterAmplitude, single.jitterAmplitude * 2, accuracy: 1e-12)
        XCTAssertEqual(double.inkLengthPerSecond, single.inkLengthPerSecond * 2, accuracy: 1e-12)
    }

    /// 无量纲与绝对时间参数不得随字号变化。
    func testDimensionlessParametersDoNotChangeWithScale() {
        let single = HandwritingFeel.humanizerConfiguration(referenceScale: 40)
        let double = HandwritingFeel.humanizerConfiguration(referenceScale: 80)

        XCTAssertEqual(double.durationVariation, single.durationVariation)
        XCTAssertEqual(double.minimumDuration, single.minimumDuration)
        XCTAssertEqual(double.basePressure, single.basePressure)
        XCTAssertEqual(double.pressureVariation, single.pressureVariation)
        XCTAssertEqual(double.minimumPressure, single.minimumPressure)
        XCTAssertEqual(double.maximumPressure, single.maximumPressure)
        XCTAssertEqual(double.taperFraction, single.taperFraction)
    }

    /// 不传参照尺度时必须落到默认字高，而不是某个隐式的 1 或 0。
    func testDefaultConfigurationUsesDefaultGlyphHeight() {
        let implicitScale = HandwritingFeel.humanizerConfiguration()
        let explicitScale = HandwritingFeel.humanizerConfiguration(
            referenceScale: HandwritingFeel.referenceGlyphHeightInPoints
        )

        XCTAssertEqual(implicitScale, explicitScale)
    }

    /// 墨线宽度同样随字号成比例，且压感越大越粗、被夹在合法区间内。
    func testInkWidthScalesWithReferenceScaleAndIsBounded() {
        let thin = PageAppearance.inkWidth(forPressure: 0, referenceScale: 40)
        let thick = PageAppearance.inkWidth(forPressure: 1, referenceScale: 40)
        let thinAtDoubleScale = PageAppearance.inkWidth(forPressure: 0, referenceScale: 80)

        XCTAssertGreaterThan(thin, 0, "落笔就该有宽度，不能是 0")
        XCTAssertGreaterThan(thick, thin)
        XCTAssertEqual(thinAtDoubleScale, thin * 2, accuracy: 1e-12)

        // 压感越界时必须夹紧，异常数据不能画出负宽度或无限粗的线。
        XCTAssertEqual(PageAppearance.inkWidth(forPressure: -5, referenceScale: 40), thin, accuracy: 1e-12)
        XCTAssertEqual(PageAppearance.inkWidth(forPressure: 5, referenceScale: 40), thick, accuracy: 1e-12)
    }

    /// 毫米与页面点的换算必须可往返，且方向正确（毫米越大，点数越多）。
    func testMillimeterPointConversionRoundTrips() {
        let millimeters: Double = 9
        let points = PageMetrics.points(fromMillimeters: millimeters)

        XCTAssertGreaterThan(points, millimeters, "一毫米应折算成多于一个页面点")
        XCTAssertEqual(PageMetrics.millimeters(fromPoints: points), millimeters, accuracy: 1e-12)
    }

    /// 默认字高换算出的页面点必须落在手写日记的合理量级。
    /// 这条不是精确断言，而是防止将来有人把基准 ppi 或字高改成荒谬值。
    func testDefaultGlyphHeightIsPlausible() {
        let heightInPoints = HandwritingFeel.referenceGlyphHeightInPoints

        XCTAssertGreaterThan(heightInPoints, 20, "字高过小，一页塞进上百行不像日记")
        XCTAssertLessThan(heightInPoints, 120, "字高过大，一页写不下几个字")
    }
}
