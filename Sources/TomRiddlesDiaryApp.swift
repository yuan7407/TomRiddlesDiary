//
//  TomRiddlesDiaryApp.swift
//  模块：App（应用入口）
//
//  文件职责：声明 App 生命周期与根场景。
//
//  设计原因：入口保持最薄，只挂载根视图，不承载任何业务、配置或依赖装配逻辑，
//  这样以后引入依赖注入或引导流程时，改动集中在下一层而不是入口。
//  注意：项目内部名沿用占位品牌，分发前必须复核并换成原创公开品牌。
//

import SwiftUI

@main
struct TomRiddlesDiaryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
