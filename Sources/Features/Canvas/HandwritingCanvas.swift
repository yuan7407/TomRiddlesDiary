//
//  HandwritingCanvas.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：把 PencilKit 的画布接进 SwiftUI，让用户能在纸上写字，
//  并在每次落笔结束后把笔画交给上层。
//
//  设计原因：
//  - 用 PencilKit 而不是自己接触摸事件：低延迟绘制、笔尖预测、压感、倾斜、
//    橡皮、撤销，这些都是 Apple 已经做好且做得比自己写好的部分。
//    自己写只会得到一个更差的画笔，还要维护。
//  - 背景色取自 `PageAppearance.paper`，与回应渲染层共用同一个值。
//    这是 D5 埋下的伏笔：两层的底色一旦有差异，墨水淡入过渡就会露出接缝。
//  - 关掉滚动与缩放：一页日记就是一页，不是无限画布。这样画布坐标与页面坐标
//    一致，笔画交给引擎时不需要额外换算（D1 的单位契约靠这个前提成立）。
//    将来若要支持翻页或缩放，必须同时处理坐标换算，不能默默打开。
//  - `PKToolPicker` 不接：产品原则是写字那张纸上不放控件。用户只有一支笔，
//    不选颜色不选粗细——魂的回应也一样。工具选择器留到确有需要时再谈。
//

import PencilKit
import SwiftUI

/// 用户手写的画布。
struct HandwritingCanvas: UIViewRepresentable {
    /// 每次一笔写完时回调，带上当前整页的手写内容。
    /// 传整页而不是单笔：成页判断、识别、字迹指标都要看整页，
    /// 而单笔可以从整页里取最后一笔。
    let onStrokeFinished: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator

        canvas.backgroundColor = UIColor(PageAppearance.paper)
        canvas.isOpaque = true

        // 一页就是一页：不滚动不缩放，画布坐标即页面坐标。
        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.bouncesZoom = false

        canvas.drawingPolicy = InteractionSettings.drawingPolicy
        canvas.tool = PKInkingTool(
            .pen,
            color: UIColor(PageAppearance.ink),
            width: PageAppearance.userInkWidth
        )

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // 回调可能在每次视图更新时换成新的闭包，协调器必须持有最新那个，
        // 否则会调到已经失效的旧闭包。
        context.coordinator.onStrokeFinished = onStrokeFinished
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStrokeFinished: onStrokeFinished)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStrokeFinished: (PKDrawing) -> Void

        init(onStrokeFinished: @escaping (PKDrawing) -> Void) {
            self.onStrokeFinished = onStrokeFinished
        }

        /// 用 `canvasViewDidEndUsingTool` 而不是 `canvasViewDrawingDidChange`：
        /// 后者在一笔的绘制过程中会连续触发，用它做成页判断会把「正在写」
        /// 误当成「写完一笔」。前者只在笔离开画布时触发一次。
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            onStrokeFinished(canvasView.drawing)
        }
    }
}
