//
//  DiaryPageView.swift
//  模块：Features/Canvas（用户书写的那张纸）
//
//  文件职责：App 的首屏，也是唯一的主界面——一张可以写字的纸。
//
//  取代原 ContentView.swift（2026-08-26）。原文件唯一的作用是把根视图指向
//  Magic Stroke Lab 诊断界面；Lab 已整体删除，这层空转的中转也一并去掉，
//  不保留只为「以后可能有用」的间接层。
//
//  当前状态是刻意的空白，不是未完成的占位符：
//  产品原则是「空白画布，让笔成为主要界面」，首屏本就应该只有纸。
//  Apple Pencil 输入（PencilKit）与「日记之魂」的回应属于计划 E，尚未接入，
//  因此现在这张纸上确实什么都不会发生。这里不放任何提示文案或按钮，
//  因为放了就要再删，而且会给出「有功能」的错误印象。
//
//  下一步（计划 E1）：在这里嵌入 PKCanvasView 承接手写，
//  并把 HandwritingReplayView 叠在同一页面坐标系上播放回应。
//

import SwiftUI

struct DiaryPageView: View {
    var body: some View {
        PageAppearance.paper
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel("日记页")
            .accessibilityHint("手写输入尚未接入，当前是一张空白的纸")
    }
}

#Preview {
    DiaryPageView()
}
