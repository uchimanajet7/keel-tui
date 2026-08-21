import Foundation

public enum TerminalDisabledBindingVisibility: Equatable, Sendable {
    case include
    case exclude
}

public enum TerminalBindingHelpKeyColumnScope: Equatable, Sendable {
    case group
    case allGroups
}

public struct TerminalKeyBindingPresentation: Equatable {
    public var id: String
    public var shortcut: String
    public var description: String
    public var compactDescription: String?
    public var groupID: String
    public var groupTitle: String
    public var retentionPriority: Int
    public var isVisible: Bool
    public var isEnabled: Bool
    public var shortcutStyle: TerminalStyle
    public var descriptionStyle: TerminalStyle

    public init(
        id: String,
        shortcut: String,
        description: String,
        compactDescription: String? = nil,
        groupID: String,
        groupTitle: String,
        retentionPriority: Int = 0,
        isVisible: Bool = true,
        isEnabled: Bool = true,
        shortcutStyle: TerminalStyle = .plain,
        descriptionStyle: TerminalStyle = .plain
    ) {
        self.id = id
        self.shortcut = shortcut
        self.description = description
        self.compactDescription = compactDescription
        self.groupID = groupID
        self.groupTitle = groupTitle
        self.retentionPriority = retentionPriority
        self.isVisible = isVisible
        self.isEnabled = isEnabled
        self.shortcutStyle = shortcutStyle
        self.descriptionStyle = descriptionStyle
    }
}

public enum TerminalKeyBindingPresentationAdapter {
    public static func statusBarItems(
        from bindings: [TerminalKeyBindingPresentation],
        disabledVisibility: TerminalDisabledBindingVisibility
    ) -> [TerminalStatusBarItem] {
        filtered(bindings, disabledVisibility: disabledVisibility).map { binding in
            TerminalStatusBarItem(
                shortcut: binding.shortcut,
                label: binding.description,
                compactLabel: binding.compactDescription,
                retentionPriority: binding.retentionPriority,
                isVisible: true,
                isEnabled: true,
                shortcutStyle: binding.shortcutStyle,
                labelStyle: binding.descriptionStyle
            )
        }
    }

    static func filtered(
        _ bindings: [TerminalKeyBindingPresentation],
        disabledVisibility: TerminalDisabledBindingVisibility
    ) -> [TerminalKeyBindingPresentation] {
        bindings.filter { binding in
            guard binding.isVisible else { return false }
            switch disabledVisibility {
            case .include:
                return true
            case .exclude:
                return binding.isEnabled
            }
        }
    }
}

public enum TerminalBindingHelp {
    public static func lines(
        from bindings: [TerminalKeyBindingPresentation],
        width: Int,
        disabledVisibility: TerminalDisabledBindingVisibility,
        keyColumnScope: TerminalBindingHelpKeyColumnScope = .allGroups,
        groupTitleStyle: TerminalStyle = .plain
    ) -> [TerminalModalLine] {
        let bindings = TerminalKeyBindingPresentationAdapter.filtered(
            bindings,
            disabledVisibility: disabledVisibility
        )
        guard !bindings.isEmpty else { return [] }

        var groupOrder: [String] = []
        var grouped: [String: [TerminalKeyBindingPresentation]] = [:]
        for binding in bindings {
            if grouped[binding.groupID] == nil {
                groupOrder.append(binding.groupID)
                grouped[binding.groupID] = []
            }
            grouped[binding.groupID, default: []].append(binding)
        }

        let allGroupsKeyWidth = bindings.map {
            TerminalDisplayWidth.width(of: $0.shortcut)
        }.max() ?? 0
        var result: [TerminalModalLine] = []

        for groupID in groupOrder {
            guard let group = grouped[groupID], !group.isEmpty else { continue }
            let groupTitle = group[0].groupTitle
            if !groupTitle.isEmpty {
                result.append(contentsOf: TerminalTextLayout.wrap(groupTitle, width: width, style: groupTitleStyle))
            }

            let keyWidth: Int
            switch keyColumnScope {
            case .group:
                keyWidth = group.map { TerminalDisplayWidth.width(of: $0.shortcut) }.max() ?? 0
            case .allGroups:
                keyWidth = allGroupsKeyWidth
            }

            for binding in group {
                result.append(
                    contentsOf: bindingLines(
                        binding,
                        keyWidth: keyWidth,
                        width: width
                    )
                )
            }
        }

        return result
    }

    private static func bindingLines(
        _ binding: TerminalKeyBindingPresentation,
        keyWidth: Int,
        width: Int
    ) -> [TerminalModalLine] {
        let spacing = 2
        let prefixWidth = keyWidth + spacing

        guard width > prefixWidth else {
            var lines = [
                TerminalModalLine(
                    segments: [
                        TerminalStyledTextSegment(binding.shortcut, style: binding.shortcutStyle)
                    ]
                )
            ]
            if !binding.description.isEmpty {
                lines.append(
                    contentsOf: TerminalTextLayout.wrap(
                        binding.description,
                        width: width,
                        style: binding.descriptionStyle
                    )
                )
            }
            return lines
        }

        let descriptionWidth = width - prefixWidth
        let wrappedDescription = TerminalTextLayout.wrap(
            binding.description,
            width: descriptionWidth,
            style: binding.descriptionStyle
        )
        let key = TerminalDisplayWidth.padRight(binding.shortcut, toWidth: keyWidth)

        return wrappedDescription.enumerated().map { index, descriptionLine in
            var segments: [TerminalStyledTextSegment] = []
            if index == 0 {
                segments.append(TerminalStyledTextSegment(key, style: binding.shortcutStyle))
            } else {
                segments.append(
                    TerminalStyledTextSegment(
                        String(repeating: " ", count: keyWidth),
                        style: binding.shortcutStyle
                    )
                )
            }
            segments.append(
                TerminalStyledTextSegment(
                    String(repeating: " ", count: spacing),
                    style: binding.descriptionStyle
                )
            )
            segments.append(contentsOf: descriptionLine.segments)
            return TerminalModalLine(segments: segments)
        }
    }
}

public extension Array where Element == TerminalKeyBindingPresentation {
    func statusBarItems(
        disabledVisibility: TerminalDisabledBindingVisibility
    ) -> [TerminalStatusBarItem] {
        TerminalKeyBindingPresentationAdapter.statusBarItems(
            from: self,
            disabledVisibility: disabledVisibility
        )
    }
}
