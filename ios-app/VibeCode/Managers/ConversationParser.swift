import Foundation

class ConversationParser {
    private var outputBuffer = ""
    private var isWaitingForUserInput = false
    private var currentMessage = ""
    private var currentSender: MessageSender = .system
    
    // Delegate for parsed messages
    weak var delegate: ConversationParserDelegate?
    
    func processOutput(_ output: String) {
        outputBuffer += output
        parseMessages()
    }
    
    private func parseMessages() {
        let lines = outputBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        
        for line in lines {
            let lineStr = String(line)
            
            // Detect Claude prompts and responses
            if lineStr.contains("Claude:") || lineStr.contains("Assistant:") {
                // Finish previous message if any
                if !currentMessage.isEmpty {
                    emitMessage()
                }
                
                // Start new Claude message
                currentSender = .claude
                currentMessage = lineStr
                    .replacingOccurrences(of: "Claude:", with: "")
                    .replacingOccurrences(of: "Assistant:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
            } else if lineStr.hasPrefix(">") || lineStr.contains("Human:") || lineStr.contains("User:") {
                // Finish previous message if any
                if !currentMessage.isEmpty {
                    emitMessage()
                }
                
                // Start new user message
                currentSender = .user
                currentMessage = lineStr
                    .replacingOccurrences(of: ">", with: "")
                    .replacingOccurrences(of: "Human:", with: "")
                    .replacingOccurrences(of: "User:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
            } else if lineStr.contains("claude") && lineStr.contains("$") {
                // This is a shell prompt, likely waiting for input
                isWaitingForUserInput = true
                
                // Finish previous message if any
                if !currentMessage.isEmpty {
                    emitMessage()
                }
                
            } else if !lineStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Continue current message
                if !currentMessage.isEmpty {
                    currentMessage += "\n"
                }
                currentMessage += lineStr
            }
        }
        
        // Clear processed buffer
        outputBuffer = ""
    }
    
    private func emitMessage() {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let message = Message(
            content: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            sender: currentSender,
            timestamp: Date()
        )
        
        delegate?.conversationParser(self, didParseMessage: message)
        
        // Reset for next message
        currentMessage = ""
    }
    
    func reset() {
        outputBuffer = ""
        currentMessage = ""
        currentSender = .system
        isWaitingForUserInput = false
    }
}

// MARK: - Enhanced Parsing

extension ConversationParser {
    private func detectMessageBoundaries(in text: String) -> [MessageBoundary] {
        var boundaries: [MessageBoundary] = []
        let lines = text.split(separator: "\n")
        
        for (index, line) in lines.enumerated() {
            let lineStr = String(line)
            
            // Common Claude patterns
            if lineStr.matches(regex: "^(Claude|Assistant):\\s*") {
                boundaries.append(MessageBoundary(
                    lineIndex: index,
                    type: .claudeStart,
                    content: lineStr
                ))
            }
            
            // User input patterns
            if lineStr.matches(regex: "^(>|Human|User):\\s*") {
                boundaries.append(MessageBoundary(
                    lineIndex: index,
                    type: .userStart,
                    content: lineStr
                ))
            }
            
            // Shell prompt patterns
            if lineStr.matches(regex: ".*\\$\\s*$") && lineStr.contains("claude") {
                boundaries.append(MessageBoundary(
                    lineIndex: index,
                    type: .shellPrompt,
                    content: lineStr
                ))
            }
        }
        
        return boundaries
    }
    
    private func extractMessagesFromBoundaries(_ boundaries: [MessageBoundary], in lines: [String]) -> [Message] {
        var messages: [Message] = []
        
        for i in 0..<boundaries.count {
            let startBoundary = boundaries[i]
            let endIndex = i + 1 < boundaries.count ? boundaries[i + 1].lineIndex : lines.count
            
            var content = ""
            for lineIndex in startBoundary.lineIndex..<endIndex {
                if lineIndex < lines.count {
                    content += lines[lineIndex] + "\n"
                }
            }
            
            // Clean up content
            content = content
                .replacingOccurrences(of: "^(Claude|Assistant|Human|User):\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !content.isEmpty {
                let sender: MessageSender
                switch startBoundary.type {
                case .claudeStart:
                    sender = .claude
                case .userStart:
                    sender = .user
                case .shellPrompt:
                    sender = .system
                }
                
                messages.append(Message(
                    content: content,
                    sender: sender,
                    timestamp: Date()
                ))
            }
        }
        
        return messages
    }
}

// MARK: - Supporting Types

protocol ConversationParserDelegate: AnyObject {
    func conversationParser(_ parser: ConversationParser, didParseMessage message: Message)
}

struct MessageBoundary {
    let lineIndex: Int
    let type: BoundaryType
    let content: String
    
    enum BoundaryType {
        case claudeStart
        case userStart
        case shellPrompt
    }
}

// MARK: - String Extensions

extension String {
    func matches(regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression) != nil
    }
}