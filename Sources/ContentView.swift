//
//  ContentView.swift
//  模块：App（根视图装配）
//
//  文件职责：决定 App 启动后显示哪个界面。
//
//  设计原因：当前只有离线 Magic Stroke Lab 可演示，因此根视图直接指向它。
//  这是临时状态：接入 PencilKit 日记页后，根视图应换成真正的日记界面，
//  Lab 降级为 DEBUG-only 工具，最终用户不应看到任何实验室控件。
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MagicStrokeLabView()
    }
}
