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
//  三个事件与它们各自的用途（2026-08-29，计划 E3c/E3d）：
//  - 落笔（`canvasViewDidBeginUsingTool`）：成页倒计时的取消点，也是打断重播的
//    触发点。必须用落笔而不是「这一笔写完」——你正在写的时候，纸不该有自己的动作。
//  - 抬笔（`canvasViewDidEndUsingTool`）：读笔画、识别、重新开始等待。
//    不用 `canvasViewDrawingDidChange`，那个在一笔的绘制过程中会连续触发。
//  - Apple Pencil 悬停：说明你还在写，用来延长等待。
//

import PencilKit
import SwiftUI

/// 用户手写的画布。
struct HandwritingCanvas: UIViewRepresentable {
    /// 这一页该显示哪份手写内容。
    ///
    /// 翻页时（计划 E3f）由上层换成新页的 drawing。**必须由外部提供**：
    /// `PKCanvasView` 自己不知道「页」这个概念，翻页对它就是换一份 drawing。
    /// 不换的话翻页之后旧页的字还留在画布上，而它属于上一页。
    let drawing: PKDrawing

    /// 笔刚落到纸上。
    let onStrokeBegan: () -> Void

    /// 每次一笔写完时回调，带上当前整页的手写内容。
    /// 传整页而不是单笔：成页判断、识别、字迹指标都要看整页，
    /// 而单笔可以从整页里取最后一笔。
    let onStrokeFinished: (PKDrawing) -> Void

    /// Apple Pencil 悬停状态变化。
    ///
    /// **硬件限制（已查证，不是可以修的问题）**：悬停只在 M2 及更新的 iPad 配
    /// Apple Pencil Pro / 二代时可用（iPad Pro M4/M5、iPad Pro 11″ 四代、
    /// iPad Pro 12.9″ 六代、iPad Air M2/M3、iPad mini A17 Pro），笔尖要进到屏幕
    /// 约 1 cm 内。来源：[Apple Pencil 技术规格](https://support.apple.com/en-us/111889)、
    /// [悬停距离实测](https://zenn.dev/usamik26/articles/pencil-hover?locale=en)。
    ///
    /// 因此在**模拟器和 iPad 10 上这个回调永远不会带 true**，成页判断走的是
    /// 没有悬停的那条路径。这是设计上接受的：悬停是加分信号，主信号不依赖它。
    let onPencilHoverChanged: (Bool) -> Void

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

        canvas.drawing = drawing
        canvas.drawingPolicy = InteractionSettings.drawingPolicy
        canvas.tool = PKInkingTool(
            .pen,
            color: UIColor(PageAppearance.ink),
            width: PageAppearance.userInkWidth
        )

        let hover = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.pencilHoverChanged(_:))
        )
        // 只接受 Apple Pencil 的触摸类型。**不加这个限制模拟器就没法开发**：
        // 鼠标指针也会产生悬停事件，指针一直在画布上就等于一直悬停，
        // 成页会被永久推后（`hoverGrace` 虽然有界，但每次轮询都会重新加一次）。
        hover.allowedTouchTypes = [UITouch.TouchType.pencil.rawValue as NSNumber]
        canvas.addGestureRecognizer(hover)

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // 回调可能在每次视图更新时换成新的闭包，协调器必须持有最新那些，
        // 否则会调到已经失效的旧闭包。
        context.coordinator.onStrokeBegan = onStrokeBegan
        context.coordinator.onStrokeFinished = onStrokeFinished
        context.coordinator.onPencilHoverChanged = onPencilHoverChanged

        // 只在真的不一样时才赋值。
        //
        // **这一条不是优化，是必须的**：每次视图更新都写一遍 `canvas.drawing`
        // 会让 PencilKit 重建整个墨迹层，用户正在写的那一笔会被打断。
        // 这和 2026-08-29 那个「笔画写完就消失」是同一类错误
        // （见 `DiaryPageModel` 文件头：高频赋值给会触发重绘的东西）。
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStrokeBegan: onStrokeBegan,
            onStrokeFinished: onStrokeFinished,
            onPencilHoverChanged: onPencilHoverChanged
        )
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStrokeBegan: () -> Void
        var onStrokeFinished: (PKDrawing) -> Void
        var onPencilHoverChanged: (Bool) -> Void

        init(
            onStrokeBegan: @escaping () -> Void,
            onStrokeFinished: @escaping (PKDrawing) -> Void,
            onPencilHoverChanged: @escaping (Bool) -> Void
        ) {
            self.onStrokeBegan = onStrokeBegan
            self.onStrokeFinished = onStrokeFinished
            self.onPencilHoverChanged = onPencilHoverChanged
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            onStrokeBegan()
        }

        /// 用 `canvasViewDidEndUsingTool` 而不是 `canvasViewDrawingDidChange`：
        /// 后者在一笔的绘制过程中会连续触发，用它做成页判断会把「正在写」
        /// 误当成「写完一笔」。前者只在笔离开画布时触发一次。
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            onStrokeFinished(canvasView.drawing)
        }

        /// 悬停手势的状态变化。
        /// `.began`/`.changed` 是笔进到范围内，其余都当成离开——
        /// 把 `.cancelled`/`.failed` 也算成离开是刻意的：宁可少延长等待，
        /// 也不能让一次异常的手势状态把成页卡住。
        @objc
        func pencilHoverChanged(_ recognizer: UIHoverGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onPencilHoverChanged(true)
            default:
                onPencilHoverChanged(false)
            }
        }
    }
}
