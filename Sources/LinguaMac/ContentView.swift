import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TranslationCore

struct ContentView: View {
    @Bindable var workspace: Workspace
    @State private var showingOptions = false
    @State private var showingOriginalImage = false
    @State private var dropTargeted = false
    @State private var showingTiming = false
    @State private var showingLanguagePair = false
    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    @AppStorage("translationSidebarVisible") private var showSidebar = false
    var body: some View {
        HStack(spacing: 0) {
            if workspace.page != .text || showSidebar {
                sidebar.frame(width: 190)
                Divider()
            }
            VStack(spacing: 0) {
                if workspace.page != .text && workspace.page != .settings {
                    header
                    Divider()
                }
                Group {
                    switch workspace.page {
                    case .text: translationDesk
                    case .glossary: GlossaryView(workspace: workspace)
                    case .history: history
                    case .settings: ModelSettingsView(workspace: workspace)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                feedback
                footer
            }
        }
        .background(CC.background).tint(.gray)
        .disclosureGroupStyle(WholeRowDisclosureStyle())
        .frame(minWidth: 1000, minHeight: 700)
        .sheet(isPresented: $showingOriginalImage) {
            if let image = workspace.originalImage ?? workspace.imagePreview {
                ImagePreviewView(image: image, name: workspace.imageName)
            }
        }
        .onChange(of: workspace.page) { _, page in if page == .text { workspace.prepareLocalModel() } }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    BrandLogo()
                    Text("Lingua").font(CC.lg)
                }
                Text(L10n.text("翻译工作台")).font(CC.sm).foregroundStyle(CC.muted)
            }.padding(.top, 24)
            VStack(spacing: 6) {
                nav(.text, icon: .text)
                Rectangle().fill(CC.border).frame(height: 0.5).padding(.vertical, 10)
                nav(.glossary, icon: .book)
                nav(.history, icon: .history)
                nav(.settings, icon: .settings)
            }
            Spacer()
            Button { workspace.page = .settings } label: {
                HStack(spacing: 7) {
                    Circle().fill(!workspace.modelIsReady ? Color.secondary.opacity(0.5) : CC.primary).frame(width: 6, height: 6)
                    Text(workspace.backend == .server ? "API · " + workspace.apiHost : (!workspace.modelIsReady ? L10n.text("设置翻译模型") : L10n.text("本地模型就绪"))).font(CC.caption).lineLimit(2)
                    Spacer()
                }.foregroundStyle(CC.muted)
            }.buttonStyle(QuietButtonStyle())

        }.padding(.horizontal, 18).padding(.bottom, 20).background(.regularMaterial)
    }
    private func nav(_ page: Workspace.Page, icon: LineIcon.Kind) -> some View {
        Button { workspace.page = page } label: {
            HStack(spacing: 12) {
                LineIcon(kind: icon)
                Text(page == .settings ? L10n.text("设置") : L10n.text(page.rawValue)).font(CC.sm.weight(workspace.page == page ? .medium : .regular)).lineLimit(1).minimumScaleFactor(0.9)
                Spacer()
            }
                .foregroundStyle(workspace.page == page ? CC.primary : Color.primary.opacity(0.75))

        }.buttonStyle(SidebarButtonStyle(selected: workspace.page == page))
            .accessibilityAddTraits(workspace.page == page ? .isSelected : [])
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(workspace.page.rawValue)).font(CC.lg)
                Text(L10n.text(subtitle)).font(CC.sm).foregroundStyle(CC.muted)
            }
            Spacer()
            if workspace.page == .text {
                Button(L10n.text("新建翻译"), action: workspace.reset).buttonStyle(NeoButtonStyle()).disabled(workspace.busy || workspace.loading)
            }
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private var subtitle: String {
        switch workspace.page {
        case .text: L10n.text("准确表达，保留每一个细节。")
        case .glossary: L10n.text("让产品名与专业术语保持一致。")
        case .history: L10n.text("保存在这台 Mac 上的最近 100 条译文。")
        case .settings: L10n.text("选择模型与运行方式，掌控本地翻译。")
        }
    }
    @ViewBuilder private var apiConsentNotice: some View {
        if workspace.backend == .server, let address = workspace.pendingAPIConsentEndpoint {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("原文（含图片识别的文字）及相关术语会发送至以下服务处理。原图不会发送。仅在同意后发送，可在设置中撤销授权。"))
                    .font(CC.sm).foregroundStyle(CC.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(address).font(CC.sm).textSelection(.enabled)
                    Spacer(minLength: 12)
                    Button(L10n.text("取消")) { workspace.pendingAPIConsentEndpoint = nil }
                        .buttonStyle(QuietButtonStyle())
                    Button(L10n.text("同意并翻译")) { workspace.approveAPIConsent(address) }
                        .buttonStyle(NeoButtonStyle(primary: true))
                        .disabled(!workspace.canTranslate || workspace.apiKeyLoading)
                }
            }.padding(.horizontal, 20).padding(.vertical, 12).background(CC.panel)
            Divider()
        }
    }
    private var translationDesk: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { showSidebar.toggle() } label: { LineIcon(kind: .sidebar) }
                    .buttonStyle(QuietButtonStyle()).help(L10n.text("显示或隐藏侧栏")).accessibilityLabel(L10n.text("切换侧栏"))
                Rectangle().fill(CC.border).frame(width: 0.5, height: 18).padding(.horizontal, 2)
                languageControl
                Spacer(minLength: 12)
                translationOptionsButton
                Button {
                    workspace.settingsBackend = workspace.backend
                    workspace.page = .settings
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape").font(.system(size: 16, weight: .regular))
                        Text(L10n.text("设置"))
                    }
                }.buttonStyle(QuietButtonStyle()).help(L10n.text("模型与设置")).accessibilityLabel(L10n.text("设置"))
            }.font(CC.sm).padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
            Divider()
            apiConsentNotice
            HStack(spacing: 0) {
                editor(isSource: true, text: $workspace.source)
                Rectangle().fill(CC.border).frame(width: 0.5)
                editor(isSource: false, text: $workspace.output)
            }
            .background(CC.card)
            .overlay { if dropTargeted { Rectangle().strokeBorder(CC.primary, lineWidth: 1.5) } }
            if !workspace.issues.isEmpty && !workspace.busy {
                DisclosureGroup(L10n.text("校对提示 · \(workspace.issues.count)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(workspace.issues.prefix(5)) { Text(L10n.text($0.message)).foregroundStyle(CC.muted) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(CC.sm).padding(14)
            }
        }
    }
    /// A single language control keeps the toolbar focused on the next translation.
    private var languageControl: some View {
        Button { showingLanguagePair.toggle() } label: {
            HStack(spacing: 10) {
                if workspace.directionMode == .bidirectional {
                    Text("\(L10n.text(workspace.myLanguage.title)) ↔ \(L10n.text(workspace.partnerLanguage.title))")
                } else {
                    Text("\(L10n.text(workspace.options.source.title)) → \(L10n.text(workspace.options.target.title))")
                }
                Text(workspace.directionMode == .bidirectional ? L10n.text("自动双向") : L10n.text("固定方向"))
                    .font(.system(size: 11)).foregroundStyle(CC.muted)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(CC.muted)
            }.font(CC.sm.weight(.medium)).padding(.horizontal, 12).frame(height: 32)
                .background(CC.panel, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(L10n.text("翻译语言与方向"))
            .help(L10n.text("选择语言或切换自动双向、固定方向"))
            .disabled(workspace.busy || workspace.loading)
            .popover(isPresented: $showingLanguagePair, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text("翻译语言")).font(CC.base.weight(.semibold))
                    Picker(L10n.text("翻译方向模式"), selection: $workspace.directionMode) {
                        ForEach(TranslationDirectionMode.allCases) { Text(L10n.text($0.title)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    Divider()
                    if workspace.directionMode == .bidirectional {
                        Picker(L10n.text("我的语言"), selection: Binding(get: { workspace.myLanguage }, set: { workspace.selectMyLanguage($0) })) {
                            ForEach(Language.allCases.filter { $0 != .auto }) { Text(L10n.text($0.title)).tag($0) }
                        }
                        Picker(L10n.text("对方语言"), selection: Binding(get: { workspace.partnerLanguage }, set: { workspace.selectPartnerLanguage($0) })) {
                            ForEach(Language.allCases.filter { $0 != .auto }) { Text(L10n.text($0.title)).tag($0) }
                        }
                        Text(L10n.text("输入我的语言时译给对方；粘贴对方的语言时译成我的语言。"))
                            .font(CC.sm).foregroundStyle(CC.muted)
                        Button(L10n.text("反转本次翻译方向"), action: workspace.swapLanguages)
                            .buttonStyle(NeoButtonStyle()).disabled(workspace.source.isEmpty)
                            .help(L10n.text("只反转当前文字的译文语言；输入新文字后继续自动判断。"))
                    } else {
                        Picker(L10n.text("原文语言"), selection: $workspace.options.source) {
                            ForEach(Language.allCases) { Text(L10n.text($0.title)).tag($0) }
                        }
                        Picker(L10n.text("译文语言"), selection: $workspace.options.target) {
                            ForEach(Language.allCases.filter { $0 != .auto }) { Text(L10n.text($0.title)).tag($0) }
                        }
                        Text(L10n.text("始终翻译成所选译文语言。"))
                            .font(CC.sm).foregroundStyle(CC.muted)
                        Button(L10n.text("交换语言"), action: workspace.swapLanguages)
                            .buttonStyle(NeoButtonStyle()).disabled(workspace.options.source == .auto)
                    }
                }.padding(22).frame(width: 320).disabled(workspace.busy || workspace.loading)
            }
    }

    private var translationOptionsButton: some View {
                Button { showingOptions.toggle() } label: {
                    LineIcon(kind: .settings)
                }.buttonStyle(QuietButtonStyle()).foregroundStyle(CC.muted).help(L10n.text("翻译选项")).accessibilityLabel(L10n.text("翻译选项"))
                    .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(L10n.text("翻译选项")).font(CC.base.weight(.semibold))
                            Picker(L10n.text("领域"), selection: $workspace.options.domain) {
                                ForEach(Domain.allCases) { Text(L10n.text($0.rawValue)).tag($0) }
                            }
                            Picker(L10n.text("风格"), selection: $workspace.options.tone) {
                                ForEach(Tone.allCases) { Text(L10n.text($0.rawValue)).tag($0) }
                            }
                            Text(L10n.text("术语表中的相关译法会自动应用。"))
                                .foregroundStyle(CC.muted)
                        }.font(CC.sm).padding(22).frame(width: 300).disabled(workspace.busy || workspace.loading)
                    }
    }
    private func languagePicker(_ title: String, selection: Binding<Language>, auto: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(Language.allCases.filter { auto || $0 != .auto }) { Text(L10n.text($0.title)).tag($0) }
        }.labelsHidden().pickerStyle(.menu).font(CC.sm.weight(.semibold))
            .fixedSize().accessibilityLabel(title).disabled(workspace.busy || workspace.loading)
    }
    private func editor(isSource: Bool, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(isSource ? L10n.text("原文") : L10n.text("译文")).foregroundStyle(CC.muted)
                if workspace.directionMode == .bidirectional {
                    Text(isSource ? (workspace.source.isEmpty ? L10n.text("自动识别") : L10n.text(workspace.automaticDirection.source.title)) : L10n.text(workspace.automaticDirection.target.title))
                        .foregroundStyle(CC.muted)
                    if !isSource, !workspace.output.isEmpty, let outputLanguage = workspace.outputLanguage, outputLanguage != workspace.automaticDirection.target {
                        Text(L10n.text("上次结果：\(L10n.text(outputLanguage.title))")).foregroundStyle(CC.muted)
                    }
                }
                Spacer()
                if isSource {
                    Menu {
                        Button(L10n.text("导入文本…"), action: workspace.importText)
                        Button(L10n.text("导入图片…"), action: workspace.importImage)
                    } label: {
                        HStack(spacing: 5) { LineIcon(kind: .plus); Text(L10n.text("导入")) }
                    }.menuStyle(.borderlessButton).fixedSize().help(L10n.text("导入文本或图片")).disabled(workspace.busy || workspace.loading)
                    Button(action: workspace.reset) { LineIcon(kind: .close) }
                        .buttonStyle(QuietButtonStyle()).help(L10n.text("清空原文和译文")).accessibilityLabel(L10n.text("清空原文和译文"))
                        .disabled(workspace.busy || workspace.loading || (workspace.source.isEmpty && workspace.output.isEmpty && workspace.imagePreview == nil))
                    if workspace.busy {
                        Button(L10n.text("停止"), action: workspace.stop).buttonStyle(NeoButtonStyle())
                    } else {
                        Button(L10n.text("翻译"), action: workspace.translate).buttonStyle(NeoButtonStyle(primary: true))
                            .keyboardShortcut(.return, modifiers: .command).help(L10n.text("Enter 翻译，Shift+Enter 换行"))
                            .disabled(!workspace.canTranslate)
                    }
                } else {
                    Button(action: workspace.copy) { LineIcon(kind: .copy) }.buttonStyle(QuietButtonStyle()).help(L10n.text("复制译文"))
                        .disabled(workspace.output.isEmpty || workspace.busy)
                    Button(action: workspace.export) { LineIcon(kind: .download) }.buttonStyle(QuietButtonStyle()).help(L10n.text("导出译文"))
                        .disabled(workspace.output.isEmpty || workspace.busy)
                }
            }.font(CC.sm).padding(.horizontal, 18).frame(height: 48).background(CC.panel)
            if isSource && workspace.imagePreview != nil { imageAttachment }
            TranslationTextEditor(text: text,
                                  placeholder: isSource ? L10n.text("输入或粘贴文字，也可拖入图片、文本文件") : L10n.text("译文将在这里显示"),
                                  editable: !workspace.busy,
                                  label: isSource ? L10n.text("原文") : L10n.text("译文"),
                                  onSubmit: isSource ? { if workspace.canTranslate { workspace.translate() } } : nil,
                                  onPasteImage: { board in isSource && workspace.pasteImage(board) })
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxHeight: .infinity)
            HStack {
                Text(L10n.text("\(text.wrappedValue.count.formatted()) 字符"))
                Spacer()
                if isSource { Text(L10n.text("Enter 翻译 · Shift+Enter 换行")) }
                if !isSource && workspace.translationDuration != nil {
                    Text(L10n.text("输入 \(workspace.generationStats.promptTokens) · 输出 \(workspace.generationStats.outputTokens) token"))
                }
            }.font(CC.caption).foregroundStyle(CC.muted).padding(.horizontal, 18).padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard isSource, urls.count == 1, let url = urls.first else { return false }
            return workspace.importFile(url)
        } isTargeted: { if isSource { dropTargeted = $0 } }
    }
    private var imageAttachment: some View {
        HStack(spacing: 10) {
            Button { showingOriginalImage = true } label: {
                HStack(spacing: 10) {
                    if let image = workspace.imagePreview {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.imageName).lineLimit(1)
                        Text(L10n.text("已识别 · 点击查看原图")).foregroundStyle(CC.muted)
                    }.font(CC.sm)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(L10n.text("查看原图"))
            .accessibilityLabel(L10n.text("查看原图"))
            Button { workspace.removeImage() } label: { LineIcon(kind: .trash) }
                .buttonStyle(QuietButtonStyle()).foregroundStyle(CC.muted).help(L10n.text("移除图片，保留文字")).disabled(workspace.busy)
        }.padding(10).background(CC.panel, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 18)
    }
    private var history: some View {
        VStack(spacing: 18) {
            TextField(L10n.text("搜索原文或译文"), text: $workspace.search).textFieldStyle(.roundedBorder).font(CC.sm)
            if workspace.filteredHistory.isEmpty {
                Spacer(); Text(workspace.search.isEmpty ? L10n.text("完成一篇翻译后，记录会出现在这里。") : L10n.text("没有找到匹配的记录。")).font(CC.base).foregroundStyle(CC.muted); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(workspace.filteredHistory) { record in
                            HStack(alignment: .top, spacing: 18) {
                                Button { workspace.restore(record) } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack { Text(L10n.text(record.options.target.title) + " · " + L10n.text(record.options.domain.rawValue)); Spacer(); Text(record.date, format: .dateTime.month().day().hour().minute()) }.font(CC.sm).foregroundStyle(CC.muted)
                                        Text(record.source).font(CC.base).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(record.translation).font(CC.sm).foregroundStyle(CC.muted).lineLimit(2)
                                    }
                                }.buttonStyle(QuietButtonStyle())
                                Button { workspace.deleteRecord(record.id) } label: { LineIcon(kind: .trash) }.buttonStyle(QuietButtonStyle()).help(L10n.text("删除这条记录"))
                            }.padding(20).ccCard()
                        }
                    }
                }
            }
        }.padding(24).disabled(workspace.busy || workspace.loading)
    }
    @ViewBuilder private var feedback: some View {
        if let message = workspace.error ?? workspace.notice {
            HStack(alignment: .top) {
                Text(L10n.text(message)).font(CC.sm).foregroundStyle(workspace.error == nil ? CC.muted : CC.primary).textSelection(.enabled)
                Spacer()
                Button(L10n.text("关闭")) { workspace.error = nil; workspace.notice = nil }.buttonStyle(QuietButtonStyle()).font(CC.sm)
            }.padding(.horizontal, 26).padding(.vertical, 12).background(CC.panel)
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                if workspace.busy || workspace.loading { ProgressView().controlSize(.small) }
                Text(workspace.loading ? (workspace.downloadingModelID == nil ? L10n.text("正在加载本地模型 · \(workspace.downloadStatus.phase.rawValue)") : L10n.text("正在下载模型 · \(workspace.downloadStatus.phase.rawValue)")) : L10n.text(workspace.status)).lineLimit(1)
                Spacer()
                Text(workspace.loading || workspace.backend == .native ? L10n.text("本地模型 · 离线翻译") : (workspace.usesRemoteAPI ? L10n.text("译文由 \(workspace.apiHost) 处理") : L10n.text("API · 本机服务")))
            }
            if workspace.loading && workspace.downloadingModelID == nil {
                Text(L10n.text("\(workspace.loadingModel) · 已用 \(String(format: "%.1f", workspace.loadElapsed)) 秒 · 模型权重与分词器加载到 App 后可重复使用"))
                    .lineLimit(2).textSelection(.enabled)
            }
            if workspace.loading || (workspace.backend == .native && !workspace.loadedModel.isEmpty) {
                HStack(spacing: 14) {
                    Text(L10n.text("应用内存 \(workspace.resources?.residentBytes.map { ModelDownloadStatus.bytes(Int64($0)) } ?? "—")"))
                        .help(L10n.text("当前 App 进程的驻留内存；不是整个系统的内存占用。"))
                    Text("CPU \(workspace.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")")
                        .help(L10n.text("App 进程 CPU 使用率；一个核心满载为 100%，多核可超过 100%。本地模型推理主要使用 GPU。"))
                    if let bytes = workspace.resources?.mlxBytes { Text(L10n.text("模型内存 \(ModelDownloadStatus.bytes(Int64(bytes)))")).help(L10n.text("本地模型运行所分配的内存，包含权重、推理数据和缓存；可能与应用内存重叠，请勿相加。")) }
                    Spacer(minLength: 0)
                    if workspace.translationStarted != nil || workspace.translationDuration != nil {
                        Text("\(workspace.generationStats.estimated ? "≈" : "")\(workspace.generationStats.outputTokens) token · \(String(format: "%.1f", workspace.generationStats.tokensPerSecond)) token/s")
                            .help(L10n.text("生成中通过分词器估算输出 token；完成后采用模型实际计数与生成耗时。输入 token：\(workspace.generationStats.promptTokens)。"))
                        Button(L10n.text("\(String(format: "%.1f", workspace.translationElapsed)) 秒")) { showingTiming.toggle() }
                            .buttonStyle(QuietButtonStyle()).help(L10n.text("查看耗时详情"))
                            .popover(isPresented: $showingTiming, arrowEdge: .top) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(L10n.text("本次翻译耗时")).font(CC.base.weight(.semibold))
                                    Text(L10n.text("等待首字：\(String(format: "%.2f", workspace.generationStats.firstTokenSeconds)) 秒"))
                                    Divider()
                                    Text(L10n.text("输入处理：\(String(format: "%.2f", workspace.generationStats.promptSeconds)) 秒"))
                                    Text(L10n.text("生成文本：\(String(format: "%.2f", workspace.generationStats.generationSeconds)) 秒"))
                                    Text(L10n.text("分词、界面及保存：\(String(format: "%.2f", max(0, workspace.translationElapsed - workspace.generationStats.promptSeconds - workspace.generationStats.generationSeconds))) 秒"))
                                    Text(L10n.text("总计：\(String(format: "%.2f", workspace.translationElapsed)) 秒"))
                                }.font(CC.sm).monospacedDigit().padding(20)
                            }
                            .help(L10n.text("输入处理 \(String(format: "%.2f", workspace.generationStats.promptSeconds)) 秒；生成 \(String(format: "%.2f", workspace.generationStats.generationSeconds)) 秒；首字等待 \(String(format: "%.2f", workspace.generationStats.firstTokenSeconds)) 秒。总耗时还包含分词、界面更新及保存记录。"))
                    } else if let duration = workspace.loadDuration, !workspace.loading {
                        Text(L10n.text("加载 \(String(format: "%.1f", duration)) 秒 · 内存驻留"))
                    }
                }.monospacedDigit()
            }
        }.font(CC.caption).foregroundStyle(CC.muted).padding(.horizontal, 26).padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(CC.border).frame(height: 0.5) }
    }
}

struct GlossaryView: View {
    @Bindable var workspace: Workspace
    @State private var source = ""
    @State private var target = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                TextField(L10n.text("原文术语"), text: $source)
                LineIcon(kind: .arrow).foregroundStyle(CC.muted)
                TextField(L10n.text("固定译法"), text: $target)
                Button(L10n.text("添加术语")) { if workspace.addTerm(source: source, target: target) { source = ""; target = "" } }.buttonStyle(NeoButtonStyle(primary: true))
            }.textFieldStyle(.roundedBorder).font(CC.base).padding(20).ccCard()
            Text(L10n.text("术语表用于提示模型，并在译文中检查是否采用指定译法。请按当前语言方向维护术语。")).font(CC.sm).foregroundStyle(CC.muted)
            if workspace.data.glossary.isEmpty {
                Spacer(); Text(L10n.text("从产品名、专有名词或行业术语开始添加。")).font(CC.base).foregroundStyle(CC.muted).frame(maxWidth: .infinity); Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workspace.data.glossary) { term in
                            HStack { Text(term.source).frame(maxWidth: .infinity, alignment: .leading); LineIcon(kind: .arrow).foregroundStyle(CC.muted); Text(term.target).frame(maxWidth: .infinity, alignment: .leading)
                                Button { workspace.deleteTerm(term.id) } label: { LineIcon(kind: .trash) }.buttonStyle(QuietButtonStyle()).help(L10n.text("删除术语"))
                            }.font(CC.base).padding(18)
                            Divider().padding(.horizontal, 18)
                        }
                    }.ccCard()
                }
            }
        }.padding(24).disabled(workspace.busy || workspace.loading)
    }
}

struct ModelSettingsView: View {
    @Bindable var workspace: Workspace
    @State private var legalDocument: LegalDocument?
    @State private var clearingHistory = false

    @AppStorage("interfaceLanguage") private var interfaceLanguage = "system"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("模型与设置")).font(CC.lg)
                    Text(L10n.text("选择本地模型，或连接你的 LLM 服务。")).font(CC.sm).foregroundStyle(CC.muted)
                }.padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L10n.text("界面语言"))
                        Spacer()
                        Picker(L10n.text("界面语言"), selection: $interfaceLanguage) {
                            ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                        }.labelsHidden().frame(width: 180)
                    }
                    Text(L10n.text("仅更改界面语言，不影响翻译语言和模型。"))
                        .font(CC.caption).foregroundStyle(CC.muted)
                }.font(CC.sm).padding(18).ccCard()
                HStack(spacing: 8) {
                    Text(L10n.text("当前翻译方式")).foregroundStyle(CC.muted)
                    Spacer()
                    Text(workspace.backend == .native ? L10n.text("本地模型 · 离线翻译") : L10n.text("API 服务 · ") + workspace.apiHost)
                        .fontWeight(.medium).lineLimit(1)
                }.font(CC.sm)
                HStack(spacing: 4) {
                    engineButton(.native, title: L10n.text("本地模型"))
                    engineButton(.server, title: L10n.text("API 服务"))
                }.padding(4).background(CC.panel, in: RoundedRectangle(cornerRadius: 10))
                    .disabled(workspace.busy || workspace.loading)
                Text(L10n.text("选择配置并查看详情；点击下方的使用按钮后切换翻译方式。"))
                    .font(CC.sm).foregroundStyle(CC.muted)
                if workspace.settingsBackend == .native { nativeSettings } else { serverSettings }
                details
            }.frame(maxWidth: 660).padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 32)
                .frame(maxWidth: .infinity)
        }
        .sheet(item: $legalDocument) { LegalDocumentsView(document: $0) }
        .confirmationDialog(L10n.text("清空全部翻译记录？"), isPresented: $clearingHistory) {
            Button(L10n.text("清空翻译记录"), role: .destructive) { workspace.clearHistory() }
            Button(L10n.text("取消"), role: .cancel) {}
        }
    }

    private func engineButton(_ backend: Workspace.Backend, title: String) -> some View {
        Button { workspace.settingsBackend = backend } label: {
            Text(title).font(CC.sm.weight(workspace.settingsBackend == backend ? .semibold : .regular))
                .foregroundStyle(workspace.settingsBackend == backend ? Color.primary : CC.muted)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(workspace.settingsBackend == backend ? CC.card : .clear, in: RoundedRectangle(cornerRadius: 7))
                 .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var nativeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("模型库")).font(CC.base.weight(.semibold))
            Text(L10n.text("仅提供应用已适配的模型。下载完成后点击使用，不支持导入其他模型文件。"))
                .font(CC.sm).foregroundStyle(CC.muted)
            HStack {
                Text(L10n.text("下载源")).font(CC.sm)
                Spacer()
                Picker(L10n.text("模型下载源"), selection: $workspace.downloadSource) {
                    ForEach(ModelDownloadSource.allCases) { Text(L10n.text($0.rawValue)).tag($0) }
                }.labelsHidden().fixedSize()
            }.disabled(workspace.busy || workspace.loading)
            if workspace.downloadSource == .custom {
                TextField("https://…", text: $workspace.customDownloadEndpoint).textFieldStyle(.roundedBorder)
                    .disabled(workspace.busy || workspace.loading)
            }
            Divider()
            ForEach(LocalModelPreset.all) { model in
                libraryRow(model)
                if model.id != LocalModelPreset.all.last?.id { Divider() }
            }
            if workspace.loading {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalModelPreset.find(workspace.downloadingModelID ?? workspace.modelKey)?.title ?? workspace.modelKey)
                            .font(CC.sm.weight(.medium))
                        Text(L10n.text(workspace.downloadStatus.phase.rawValue)).font(CC.sm)
                        if workspace.downloadStatus.total > 0 {
                            ProgressView(value: workspace.downloadStatus.fraction)
                            HStack {
                                Text("\(workspace.downloadStatus.completedText) / \(workspace.downloadStatus.totalText)")
                                Spacer()
                                Text("\(Int(workspace.downloadStatus.fraction * 100))% · \(workspace.downloadStatus.speedText)")
                            }.font(CC.caption).monospacedDigit()
                        } else { ProgressView().controlSize(.small) }
                        if !workspace.downloadStatus.file.isEmpty {
                            Text(workspace.downloadStatus.file).font(CC.caption).lineLimit(1).truncationMode(.middle)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(L10n.text("取消"), action: workspace.stop).buttonStyle(NeoButtonStyle())
                }
            }
        }.padding(22).ccCard()
    }

    private func libraryRow(_ model: LocalModelPreset) -> some View {
        let installed = workspace.modelIsDownloaded(model.id)
        let bundled = workspace.modelIsBundled(model.id)
        let active = workspace.backend == .native && workspace.loadedModel == model.id
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.title).font(CC.sm.weight(.semibold)).textSelection(.enabled)
                    HStack(spacing: 8) {
                        if bundled { Text(L10n.text("内置")) }
                        Text(L10n.text("约 \(ModelDownloadStatus.bytes(model.downloadBytes))"))
                        Text(active ? L10n.text("当前使用") : (installed ? L10n.text("已下载") : L10n.text("未下载")))
                    }.font(CC.caption).foregroundStyle(CC.muted)
                }
                Spacer(minLength: 8)
                if active {
                    Text(L10n.text("使用中")).font(CC.sm).foregroundStyle(CC.muted)
                } else if installed {
                    Button(L10n.text("使用")) { workspace.useLibraryModel(model.id) }
                        .buttonStyle(NeoButtonStyle()).disabled(workspace.busy || workspace.loading)
                } else {
                    Button(L10n.text("下载")) { workspace.downloadLibraryModel(model.id) }
                        .buttonStyle(NeoButtonStyle()).disabled(workspace.busy || workspace.loading)
                }
            }
            Text(L10n.text(model.summary)).font(CC.sm).foregroundStyle(CC.muted)
        }.padding(.vertical, 3)
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).foregroundStyle(.primary).frame(width: 112, alignment: .leading)
            content()
        }.font(CC.sm).frame(minHeight: 54)
    }

    private var serverSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("连接 LLM 服务")).font(CC.base.weight(.semibold))
                Text(L10n.text("选择服务，填写模型名称和 API Key。")).font(CC.sm).foregroundStyle(CC.muted)
            }.padding(22)
            Divider().padding(.horizontal, 22)
            VStack(alignment: .leading, spacing: 0) {
                settingRow(L10n.text("服务商")) {
                    Picker(L10n.text("API 服务商"), selection: Binding(get: { workspace.apiProvider }, set: {
                        workspace.selectAPIProvider($0)
                    })) {
                        ForEach(APIProvider.allCases) { Text(L10n.text($0.title)).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
                Text(L10n.text(workspace.apiProvider.help)).font(CC.sm).foregroundStyle(CC.muted).padding(.bottom, 16)
                Divider()
                settingRow(L10n.text("服务地址")) {
                    if workspace.apiProvider == .custom {
                        TextField(L10n.text("例如 https://api.example.com/v1"), text: $workspace.endpoint)
                            .textFieldStyle(.roundedBorder)
                    } else { Text(workspace.endpoint).foregroundStyle(CC.muted).textSelection(.enabled) }
                }
                Divider()
                settingRow(L10n.text("模型名称")) {
                    TextField(L10n.text("填写服务商提供的模型 ID"), text: $workspace.serverModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(L10n.text("API 模型名称"))
                        .help(L10n.text("使用服务商控制台或文档中的完整模型 ID。"))
                }
                Text(L10n.text("从服务商控制台或 API 文档复制完整模型 ID，App 会按填写的名称调用。"))
                    .font(CC.sm).foregroundStyle(CC.muted).padding(.bottom, 16)
                Divider()
                settingRow("API Key") {
                    SecureField(workspace.apiProvider.keyURL == nil ? L10n.text("无需认证时可留空") : L10n.text("粘贴服务商的 API Key"), text: $workspace.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button(workspace.apiKeySaved ? L10n.text("已保存") : L10n.text("保存"), action: workspace.saveAPIKey)
                        .buttonStyle(NeoButtonStyle()).disabled(workspace.apiKeySaved || workspace.apiKeyLoading)
                }
                if workspace.apiKeyLoading { Text(L10n.text("正在读取 API 凭据，请稍候。")).font(CC.caption).foregroundStyle(CC.muted) }
                if let url = workspace.apiProvider.keyURL {
                    Link(L10n.text("获取 API Key ↗"), destination: url).font(CC.sm).foregroundStyle(CC.primary).padding(.bottom, 12)
                }
            }.padding(.horizontal, 22)
            VStack(alignment: .leading, spacing: 7) {
                Text(workspace.usesRemoteAPI ? L10n.text("原文及相关术语会发送至 \(workspace.apiHost)。") : L10n.text("原文发送至你配置的服务。远程地址需 HTTPS，本机可用 HTTP。"))
                Text(L10n.text("Key 默认用于本次会话；点击保存后存入应用本地存储。"))
            }.font(CC.sm).foregroundStyle(CC.muted).padding(22).padding(.top, -8)
            HStack {
                Text(workspace.backend == .server ? L10n.text("当前使用 API 服务") : L10n.text("当前使用本地模型"))
                    .font(CC.sm).foregroundStyle(CC.muted)
                Spacer()
                Button(workspace.backend == .server ? L10n.text("正在使用此 API") : L10n.text("使用此 API 翻译")) {
                    workspace.selectBackend(.server)
                }.buttonStyle(NeoButtonStyle(primary: true)).disabled(workspace.backend == .server)
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }.ccCard().disabled(workspace.busy || workspace.loading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisclosureGroup(L10n.text("下载与模型说明")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("国内镜像由第三方提供，仅下载公开模型，不发送账号 Token。缓存文件会直接复用；下载前请确认模型许可。"))
                    Text(L10n.text("本地翻译仅支持模型库中已适配的模型。模型由应用下载和管理，不支持导入文件夹或自行指定模型仓库。下载大小不等于运行内存。"))
                    Text(L10n.text("API 服务需支持 chat/completions 接口与 system / user 消息，根地址通常以 /v1 结尾。请求拒绝重定向，不会自动启动本机服务。"))
                }.padding(.top, 10).foregroundStyle(CC.muted)
            }
            Divider()
            DisclosureGroup(L10n.text("数据与隐私")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("OCR 与本地模型翻译在本机处理；API 模式会将原文及相关术语发送至配置的服务，由该服务处理。术语表与最近 100 条记录仍保存在 Application Support/LinguaMac。"))
                    Text(L10n.text("记录为普通本地文件，可使用 FileVault 保护设备。数字与术语提示仅辅助校对，专业文档需人工复核。"))
                    HStack {
                        Button(L10n.text("隐私政策")) { legalDocument = .privacy }
                        Button(L10n.text("开源许可")) { legalDocument = .licenses }
                    }.buttonStyle(QuietButtonStyle())
                    Button(L10n.text("撤销 API 发送授权")) { workspace.revokeAPIConsent() }.buttonStyle(QuietButtonStyle())
                    Button(L10n.text("清空翻译记录")) { clearingHistory = true }
                        .buttonStyle(QuietButtonStyle()).disabled(workspace.busy || workspace.loading || workspace.data.history.isEmpty)
                }.padding(.top, 10).foregroundStyle(CC.muted)
            }
        }.font(CC.sm).padding(.horizontal, 4)
    }
}
