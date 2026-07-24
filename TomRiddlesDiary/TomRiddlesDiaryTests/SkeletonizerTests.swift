@testable import TomRiddlesDiary
import XCTest

@MainActor
final class SkeletonizerTests: XCTestCase {
    private let skeletonizer = Skeletonizer()

    func testEmptyMaskIsUnchanged() {
        let input = BinaryMask(width: 7, height: 5)
        XCTAssertEqual(skeletonizer.skeletonize(input), input)
    }

    func testAlreadyThinLineIsStable() {
        let input = MaskFixtures.mask([
            ".....",
            "..#..",
            "..#..",
            "..#..",
            ".....",
        ])

        XCTAssertEqual(skeletonizer.skeletonize(input), input)
    }

    func testThickShapeBecomesSmallerWithoutLosingConnectivity() {
        let input = MaskFixtures.mask([
            ".......",
            "..###..",
            "..###..",
            "..###..",
            "..###..",
            "..###..",
            ".......",
        ])

        let output = skeletonizer.skeletonize(input)

        XCTAssertGreaterThan(output.foregroundCount, 0)
        XCTAssertLessThan(output.foregroundCount, input.foregroundCount)
        XCTAssertTrue(MaskFixtures.isEightConnected(output))
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
    }

    func testSkeletonizerNeverAddsForegroundPixels() {
        let input = MaskFixtures.mask([
            ".........",
            "..#####..",
            "..#####..",
            "..#####..",
            "....###..",
            "....###..",
            ".........",
        ])

        let output = skeletonizer.skeletonize(input)
        let inputPoints = Set(input.foregroundPoints)

        XCTAssertTrue(Set(output.foregroundPoints).isSubset(of: inputPoints))
    }

    func testThinLoopSurvives() {
        let input = MaskFixtures.mask([
            ".......",
            ".#####.",
            ".#...#.",
            ".#...#.",
            ".#...#.",
            ".#####.",
            ".......",
        ])

        let output = skeletonizer.skeletonize(input)

        XCTAssertGreaterThan(output.foregroundCount, 0)
        XCTAssertTrue(MaskFixtures.isEightConnected(output))
    }

    func testSkeletonizationIsIdempotent() {
        let input = MaskFixtures.mask([
            ".........",
            "...###...",
            "..#####..",
            ".#######.",
            "..#####..",
            "...###...",
            ".........",
        ])

        let once = skeletonizer.skeletonize(input)
        let twice = skeletonizer.skeletonize(once)

        XCTAssertEqual(twice, once)
    }

    func testTinyDimensionsAreReturnedSafely() {
        var input = BinaryMask(width: 2, height: 2)
        input[0, 0] = true
        input[1, 1] = true

        XCTAssertEqual(skeletonizer.skeletonize(input), input)
    }

    func testForegroundTouchingEveryMaskEdgeStillThins() {
        let input = MaskFixtures.mask([
            "###",
            "###",
            "###",
        ])

        let output = skeletonizer.skeletonize(input)

        XCTAssertGreaterThan(output.foregroundCount, 0)
        XCTAssertLessThan(output.foregroundCount, input.foregroundCount)
        XCTAssertTrue(MaskFixtures.isEightConnected(output))
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
    }

    func testSolidTwoByTwoComponentNeverDisappears() {
        let input = MaskFixtures.mask([
            "##",
            "##",
        ])

        let output = skeletonizer.skeletonize(input)

        XCTAssertEqual(output.foregroundCount, 1)
        XCTAssertTrue(Set(output.foregroundPoints).isSubset(of: Set(input.foregroundPoints)))
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
    }
}
