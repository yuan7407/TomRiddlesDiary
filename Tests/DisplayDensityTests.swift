//
//  DisplayDensityTests.swift
//  测试目标：Configuration 的 PageMetrics（毫米 ↔ 页面点）。
//
//  为什么这样测：密度选错不会报错，只会让所有字悄悄偏大或偏小几个百分点，
//  所以把 iPhone Duo 的基准值和「9 毫米是多少点」各钉一条。数值出处见 PageMetrics 文件头。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class DisplayDensityTests: XCTestCase {
    func testDensityIsTheDuoScreen() {
        XCTAssertEqual(PageMetrics.pointsPerInch, 460.0 / 3.0, accuracy: 1e-9)
    }

    func testNineMillimetresInPoints() {
        XCTAssertEqual(PageMetrics.points(fromMillimeters: 9), 54.33, accuracy: 0.01)
    }

    func testMillimetreConversionRoundTrips() {
        XCTAssertEqual(PageMetrics.millimeters(fromPoints: PageMetrics.points(fromMillimeters: 9)), 9, accuracy: 1e-9)
    }
}
