//
//  Project.swift
//  osaurus
//
//  A user-facing container that groups chat sessions around a topic.
//  Orthogonal to agents: a project can hold conversations from any agent.
//

import Foundation

/// A named grouping of chat sessions with optional shared context.
public struct Project: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    /// Free-form instructions prepended to the system prompt of every chat
    /// in this project. Empty string means no extra context.
    public var instructions: String
    /// Knowledge collections shared by all chats in this project. Merged
    /// with the agent's own `knowledgeCollectionIds` at request time.
    public var knowledgeCollectionIds: [UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        instructions: String = "",
        knowledgeCollectionIds: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.knowledgeCollectionIds = knowledgeCollectionIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        knowledgeCollectionIds =
            try c.decodeIfPresent([UUID].self, forKey: .knowledgeCollectionIds) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, instructions, knowledgeCollectionIds, createdAt, updatedAt
    }
}
