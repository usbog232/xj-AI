import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var recording: RecordingStore
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedSessionIDs = Set<UUID>()
    @State private var showsDeleteConfirmation = false
    @State private var showsDownloadOptions = false
    @State private var downloadOptions = SessionDownloadOptions()

    private var filteredSessions: [SessionRecord] {
        guard !searchText.isEmpty else { return sessions.sessions }
        return sessions.sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSelecting {
                selectionToolbar
            } else {
                HStack(spacing: 10) {
                    Text("记录")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("选择") {
                        isSelecting = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppTheme.live)
                    .disabled(filteredSessions.isEmpty || recording.phase.isBusy)

                    Button { recording.newIdleSession() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("新建实时会话 (⌘N)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }

            if !isSelecting {
                Button { recording.newIdleSession() } label: {
                    Label("新建实时会话", systemImage: "plus.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .xjControlSurface()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredSessions) { session in
                        Button {
                            if isSelecting {
                                toggleSelection(session.id)
                            } else {
                                sessions.selectedSessionID = session.id
                            }
                        } label: {
                            SidebarSessionRow(
                                session: session,
                                isSelected: isSelecting
                                    ? selectedSessionIDs.contains(session.id)
                                    : sessions.selectedSessionID == session.id,
                                showsCheckbox: isSelecting,
                                isChecked: selectedSessionIDs.contains(session.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            SearchField(text: $searchText)
                .padding(12)
        }
        .background(.ultraThinMaterial)
        .alert("删除选中的记录？", isPresented: $showsDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if recording.deleteSessions(withIDs: selectedSessionIDs) {
                    selectedSessionIDs.removeAll()
                    isSelecting = false
                }
            }
        } message: {
            Text("将永久删除 \(selectedSessionIDs.count) 条记录，以及保存在本地的录音、会话 JSON 和已导出字幕文件。")
        }
        .onChange(of: sessions.sessions.map(\.id)) { _, availableIDs in
            selectedSessionIDs.formIntersection(Set(availableIDs))
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedSessionIDs.count) 项")
                .font(.system(size: 12, weight: .semibold))

            Button(allVisibleSelected ? "取消全选" : "全选") {
                if allVisibleSelected {
                    selectedSessionIDs.subtract(filteredSessions.map(\.id))
                } else {
                    selectedSessionIDs.formUnion(filteredSessions.map(\.id))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Button {
                showsDownloadOptions.toggle()
            } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .buttonStyle(.plain)
            .disabled(selectedSessionIDs.isEmpty || recording.phase.isBusy)
            .help("下载选中记录")
            .popover(isPresented: $showsDownloadOptions, arrowEdge: .top) {
                SessionDownloadOptionsView(
                    selectionCount: selectedSessionIDs.count,
                    options: $downloadOptions
                ) {
                    showsDownloadOptions = false
                    recording.downloadSessions(
                        withIDs: selectedSessionIDs,
                        options: downloadOptions
                    )
                }
            }

            Button {
                showsDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedSessionIDs.isEmpty ? Color.secondary : Color.red)
            .disabled(selectedSessionIDs.isEmpty || recording.phase.isBusy)
            .help("删除选中记录及本地文件")

            Button {
                selectedSessionIDs.removeAll()
                isSelecting = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("退出选择")
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
        }
    }

    private var allVisibleSelected: Bool {
        !filteredSessions.isEmpty && filteredSessions.allSatisfy { selectedSessionIDs.contains($0.id) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedSessionIDs.contains(id) {
            selectedSessionIDs.remove(id)
        } else {
            selectedSessionIDs.insert(id)
        }
    }
}

private struct SessionDownloadOptionsView: View {
    let selectionCount: Int
    @Binding var options: SessionDownloadOptions
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("下载选中记录")
                .font(.system(size: 14, weight: .semibold))

            Picker("内容类型", selection: $options.kind) {
                ForEach(SessionDownloadKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if options.kind == .subtitles {
                LabeledContent("字幕内容") {
                    Picker("字幕内容", selection: $options.subtitleContent) {
                        ForEach(SubtitleDownloadContent.allCases) { content in
                            Text(content.title).tag(content)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }

                LabeledContent("字幕格式") {
                    Picker("字幕格式", selection: $options.subtitleFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }
            } else {
                LabeledContent("音频格式") {
                    Picker("音频格式", selection: $options.audioFormat) {
                        ForEach(AudioDownloadFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 112)
                }

                Text(options.audioFormat == .mp3
                     ? "MP3 使用 128 kbps，适合分享和节省空间。"
                     : "WAV 使用 16-bit PCM，适合后期处理。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onDownload) {
                Label("导出 \(selectionCount) 条…", systemImage: "arrow.down.to.line")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct SidebarSessionRow: View {
    let session: SessionRecord
    let isSelected: Bool
    let showsCheckbox: Bool
    let isChecked: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showsCheckbox {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
            } else {
                Image(systemName: session.duration > 0 ? "waveform" : "text.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(session.createdAt.xjShortStamp) · \(TimeFormatters.clock(session.duration))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(isSelected ? Color.white.opacity(0.09) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(AppTheme.live)
                    .frame(width: 3, height: 34)
                    .offset(x: -1)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索会话", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .xjControlSurface()
    }
}
