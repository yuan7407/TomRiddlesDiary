//
//  TomRiddlesDiaryApp.swift
//  模块：App（应用入口）
//
//  文件职责：声明 App 生命周期与根场景。
//
//  设计原因：入口保持最薄，只挂载根视图，不承载任何业务、配置或依赖装配逻辑，
//  这样以后引入依赖注入或引导流程时，改动集中在下一层而不是入口。
//  2026-08-26 起直接挂载 DiaryPageView：原先经 ContentView 中转是为了指向
//  已删除的 Lab 诊断界面，那层间接已无意义。
//  启动时唯一做的事是注册印刷体字体（计划 P2）：字体必须在第一个视图画出来之前就位，
//  否则第一帧的页眉会先用系统字体画一次再跳成宋体。
//

import SwiftUI

@main
struct TomRiddlesDiaryApp: App {
    init() {
        PrintedType.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            DiaryPageView()
                // 纸永远是白天的纸：手机开着深色模式时，PencilKit 会把黑墨水反转成浅灰（2026-11-18 真机
                // 「写字是浅灰色的」），整本书也不该跟着系统变暗。
                .preferredColorScheme(.light)
        }
    }
}
