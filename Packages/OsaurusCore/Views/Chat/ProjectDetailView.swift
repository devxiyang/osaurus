//
//  ProjectDetailView.swift
//  osaurus
//
//  Full-content project page: name, shared instructions, and the
//  conversations grouped under the project. Shown in the chat window's
//  content area when a project is opened from the sidebar's Projects tab.
//

import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    /// Open a conversation (the host closes this page and loads it).
    let onOpenSession: (ChatSessionData) -> Void
    /// Start a new chat inside this project.
    let onNewChat: () -> Void
    /// Delete the project (host detaches member chats and closes the page).
    /// Called after this view's own confirmation dialog.
    let onDelete: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.themedAlertScope) private var alertScope
    @ObservedObject private var sessionsManager = ChatSessionsManager.shared
    @ObservedObject private var knowledgeManager = KnowledgeManager.shared
    /// Draft of the instructions editor. Saved explicitly; `hasEdits`
    /// drives the Save button's visibility.
    @State private var instructionsDraft: String = ""
    @State private var loadedProjectId: UUID?
    @State private var searchQuery: String = ""
    @FocusState private var isSearchFocused: Bool
    /// Member session ids whose message bodies match the query, resolved
    /// asynchronously against the chat-history database (debounced per
    /// keystroke), mirroring the sidebar's content search.
    @State private var contentMatchedSessionIds: Set<UUID> = []
    @State private var contentSearchTask: Task<Void, Never>?
    @State private var isContentSearchInFlight: Bool = false

    private var memberSessions: [ChatSessionData] {
        sessionsManager.sessions.filter { $0.projectId == project.id && !$0.archived }
    }

    /// Members after applying the search query (title + full-text content).
    private var visibleSessions: [ChatSessionData] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return memberSessions }
        return memberSessions.filter { session in
            SearchService.matches(query: trimmed, in: session.title)
                || contentMatchedSessionIds.contains(session.id)
        }
    }

    /// Debounced full-text lookup, same contract as the sidebar's: the
    /// in-memory sessions are metadata-only, so content matching goes to
    /// the chat-history database.
    private func scheduleContentSearch(_ query: String) {
        contentSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            contentMatchedSessionIds = []
            isContentSearchInFlight = false
            return
        }
        isContentSearchInFlight = true
        contentSearchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let ids = await ChatSessionStore.sessionIds(withContentContaining: trimmed)
            guard !Task.isCancelled else { return }
            contentMatchedSessionIds = ids
            isContentSearchInFlight = false
        }
    }

    private var hasEdits: Bool {
        instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            != project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                instructionsSection
                // Only meaningful once the user has knowledge collections;
                // the empty case would just advertise an unrelated feature.
                if !knowledgeManager.collections.isEmpty {
                    knowledgeSection
                }
                conversationsSection
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 32)
            .padding(.top, 64)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.primaryBackground)
        .onAppear { syncDraft() }
        // The knowledge registry loads lazily off-main (launch-hang fix);
        // in a chat window this page may be its first consumer, so settle
        // it here or the Knowledge section stays hidden behind an empty
        // `collections`.
        .task { await knowledgeManager.ensureLoaded() }
        // Same view instance can be repointed at another project (sidebar
        // click while the page is open) — reload the draft for the new one.
        .onChange(of: project.id) { _, _ in syncDraft() }
    }

    private func syncDraft() {
        guard loadedProjectId != project.id else { return }
        loadedProjectId = project.id
        instructionsDraft = project.instructions
        searchQuery = ""
        contentSearchTask?.cancel()
        contentMatchedSessionIds = []
        isContentSearchInFlight = false
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.accentColor.opacity(theme.isDark ? 0.2 : 0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(theme.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: project.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                Text("\(memberSessions.count) conversations", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
            }

            Spacer()

            Menu {
                Button(action: requestRename) { Text("Rename", bundle: .module) }
                Divider()
                Button(role: .destructive, action: requestDelete) {
                    Text("Delete", bundle: .module)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.secondaryBackground.opacity(0.5)))
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Instructions", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                Spacer()
                if hasEdits {
                    Button(action: saveInstructions) {
                        Text("Save", bundle: .module)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }

            Text("Shared context added to every chat in this project.", bundle: .module)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryText)

            TextEditor(text: $instructionsDraft)
                .font(.system(size: 12))
                .foregroundColor(theme.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90, maxHeight: 180)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.secondaryBackground.opacity(theme.isDark ? 0.35 : 0.5))
                )
        }
        .animation(theme.animationQuick(), value: hasEdits)
    }

    private func saveInstructions() {
        var updated = project
        updated.instructions = instructionsDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        ProjectManager.shared.update(updated)
    }

    // MARK: - Knowledge

    /// Toggle rows granting knowledge collections to this project. Granted
    /// collections are searchable from every chat in the project (unioned
    /// with the agent's own grants at request time).
    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge", bundle: .module)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.primaryText)

            Text("Collections every chat in this project can search.", bundle: .module)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryText)

            VStack(spacing: 2) {
                ForEach(knowledgeManager.collections) { collection in
                    knowledgeToggleRow(collection)
                }
            }
        }
    }

    private func knowledgeToggleRow(_ collection: KnowledgeCollection) -> some View {
        let isGranted = project.knowledgeCollectionIds.contains(collection.id)
        return Button {
            toggleCollection(collection.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isGranted ? theme.accentColor : theme.secondaryText.opacity(0.6))
                Image(systemName: "books.vertical")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 16)
                Text(verbatim: collection.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isGranted ? theme.accentColor.opacity(theme.isDark ? 0.10 : 0.07) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleCollection(_ id: UUID) {
        var updated = project
        if let index = updated.knowledgeCollectionIds.firstIndex(of: id) {
            updated.knowledgeCollectionIds.remove(at: index)
        } else {
            updated.knowledgeCollectionIds.append(id)
        }
        ProjectManager.shared.update(updated)
    }

    // MARK: - Conversations

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conversations", bundle: .module)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                Spacer()
                Button(action: onNewChat) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text("New Chat", bundle: .module)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(theme.accentColor)
                }
                .buttonStyle(.plain)
            }

            if !memberSessions.isEmpty {
                SidebarSearchField(
                    text: $searchQuery,
                    placeholder: "Search conversations...",
                    isFocused: $isSearchFocused,
                    isSearching: isContentSearchInFlight
                )
                .onChange(of: searchQuery) { _, query in
                    scheduleContentSearch(query)
                }
            }

            if memberSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22))
                        .foregroundColor(theme.secondaryText.opacity(0.5))
                    Text("No conversations yet", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if visibleSessions.isEmpty, isContentSearchInFlight {
                // Don't claim "no matches" while the async content lookup
                // is still running.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching conversations…", bundle: .module)
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if visibleSessions.isEmpty {
                Text("No matches found", bundle: .module)
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondaryText.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleSessions) { session in
                        ProjectConversationRow(session: session) {
                            onOpenSession(session)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rename / Delete

    private func requestRename() {
        let requestId = UUID()
        let scope = alertScope
        let sheet = ProjectNamePromptSheet(
            initialName: project.name,
            submitLabel: "Save"
        ) { name in
            ThemedAlertCenter.shared.dismiss(scope: scope, id: requestId)
            var updated = project
            updated.name = name
            ProjectManager.shared.update(updated)
        }
        ThemedAlertCenter.shared.present(
            ThemedAlertRequest(
                id: requestId,
                title: "Rename Project",
                message: nil,
                buttons: [.cancel(L("Cancel"))],
                showsCloseButton: true,
                customContent: AnyView(sheet),
                width: 360,
                onDismiss: {
                    ThemedAlertCenter.shared.dismiss(scope: scope, id: requestId)
                }
            ),
            scope: scope
        )
    }

    private func requestDelete() {
        let requestId = UUID()
        let scope = alertScope
        ThemedAlertCenter.shared.present(
            ThemedAlertRequest(
                id: requestId,
                title: "Delete Project?",
                message: L(
                    "\"\(project.name)\" will be removed. Its conversations are kept and move out of the project."
                ),
                buttons: [
                    .cancel(L("Cancel")),
                    .destructive(L("Delete")) { onDelete() },
                ],
                onDismiss: {
                    ThemedAlertCenter.shared.dismiss(scope: scope, id: requestId)
                }
            ),
            scope: scope
        )
    }
}

// MARK: - Conversation Row

private struct ProjectConversationRow: View {
    let session: ChatSessionData
    let onOpen: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.secondaryText)
                    .frame(width: 16)

                Text(verbatim: session.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(verbatim: formatRelativeDate(session.updatedAt))
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? theme.secondaryBackground.opacity(0.5) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
