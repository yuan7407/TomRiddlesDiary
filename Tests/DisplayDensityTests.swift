//
//  DisplayDensityTests.swift
//  测试目标：Configuration 的 DisplayDensity / PageMetrics（毫米 ↔ 页面点）。
//
//  为什么这样测：项目从 iPad 转到 iPhone Duo 以后，「9 毫米的字」必须在两种设备上都是 9 毫米。
//  密度选错不会报错，只会让所有字悄悄偏大或偏小几个百分点，所以把两个家族各钉一条。
//

import XCTest
@testable import TomRiddlesDiary

nonisolated final class DisplayDensityTests: XCTestCase {
    func testIPadKeepsTheDensityTheProjectAlwaysUsed() {
        XCTAssertEqual(DisplayDensity.pointsPerInch(forMachine: "iPad16,3"), 132)
    }

    func testIPhoneUsesTheDuoInnerDisplay() {
        XCTAssertEqual(DisplayDensity.pointsPerInch(forMachine: "iPhone19,1"), 430.0 / 3.0, accuracy: 1e-9)
    }

    func testUnknownMachinesFallBackToTheOldValue() {
        XCTAssertEqual(DisplayDensity.pointsPerInch(forMachine: ""), 132)
        XCTAssertEqual(DisplayDensity.pointsPerInch(forMachine: "arm64"), 132, "测试宿主认不出机型时不许换成新值")
    }

    func testNineMillimetresIsLargerInPointsOnTheDenserDisplay() {
        let onPad = 9 * DisplayDensity.iPadPointsPerInch / 25.4
        let onDuo = 9 * DisplayDensity.iPhoneDuoPointsPerInch / 25.4
        XCTAssertEqual(onPad, 46.77, accuracy: 0.01)
        XCTAssertEqual(onDuo, 50.79, accuracy: 0.01)
    }

    func testMillimetreConversionRoundTrips() {
        XCTAssertEqual(PageMetrics.millimeters(fromPoints: PageMetrics.points(fromMillimeters: 9)), 9, accuracy: 1e-9)
    }
}
