import SwiftUI

public enum EIColor {
    // MARK: - Background Scale
    public static let deep     = Color(red: 10/255, green: 10/255, blue: 15/255)
    public static let surface  = Color(red: 19/255, green: 19/255, blue: 24/255)
    public static let card     = Color(red: 26/255, green: 26/255, blue: 34/255)
    public static let elevated = Color(red: 34/255, green: 34/255, blue: 48/255)
    public static let hover    = Color(red: 42/255, green: 42/255, blue: 58/255)

    // MARK: - Border
    public static let border       = Color(red: 31/255, green: 31/255, blue: 46/255)
    public static let borderSubtle = Color(red: 24/255, green: 24/255, blue: 31/255)

    // MARK: - Text
    public static let textPrimary   = Color(red: 235/255, green: 235/255, blue: 240/255)
    public static let textSecondary = Color(red: 139/255, green: 139/255, blue: 158/255)
    public static let textTertiary  = Color(red: 92/255, green: 92/255, blue: 112/255)

    // MARK: - Accent
    public static let gold    = Color(red: 232/255, green: 168/255, blue: 73/255)
    public static let indigo  = Color(red: 124/255, green: 140/255, blue: 245/255)
    public static let emerald = Color(red: 61/255, green: 214/255, blue: 140/255)
    public static let rose    = Color(red: 244/255, green: 114/255, blue: 182/255)
    public static let violet  = Color(red: 167/255, green: 139/255, blue: 250/255)
    public static let blue    = Color(red: 96/255, green: 165/255, blue: 250/255)
    public static let red     = Color(red: 248/255, green: 113/255, blue: 113/255)

    // MARK: - Accent Dim (12% opacity backgrounds)
    public static let goldDim    = gold.opacity(0.12)
    public static let indigoDim  = indigo.opacity(0.12)
    public static let emeraldDim = emerald.opacity(0.12)
    public static let roseDim    = rose.opacity(0.12)
    public static let violetDim  = violet.opacity(0.12)
    public static let blueDim    = blue.opacity(0.12)
}

public enum EISource: String, CaseIterable, Sendable {
    case email
    case slack
    case meeting
    case transcript
    case file
    case finance

    public var color: Color {
        switch self {
        case .email:      return EIColor.gold
        case .slack:       return EIColor.indigo
        case .meeting:     return EIColor.violet
        case .transcript:  return EIColor.blue
        case .file:        return EIColor.emerald
        case .finance:     return EIColor.rose
        }
    }

    public var sfSymbol: String {
        switch self {
        case .email:      return "envelope.fill"
        case .slack:       return "bubble.left.fill"
        case .meeting:     return "video.fill"
        case .transcript:  return "text.quote"
        case .file:        return "doc.fill"
        case .finance:     return "dollarsign.circle.fill"
        }
    }

    public var label: String {
        switch self {
        case .email:      return "Email"
        case .slack:       return "Slack"
        case .meeting:     return "Meeting"
        case .transcript:  return "Transcript"
        case .file:        return "File"
        case .finance:     return "Finance"
        }
    }

    public var dimColor: Color {
        color.opacity(0.12)
    }
}

public enum EITypography {
    public static func metric() -> Font {
        .system(size: 36, weight: .bold)
    }

    public static func display() -> Font {
        .system(size: 28, weight: .bold)
    }

    public static func headline() -> Font {
        .system(size: 22, weight: .semibold)
    }

    public static func title() -> Font {
        .system(size: 20, weight: .semibold)
    }

    public static func bodyLarge() -> Font {
        .system(size: 15, weight: .medium)
    }

    public static func body() -> Font {
        .system(size: 14, weight: .regular)
    }

    public static func bodySmall() -> Font {
        .system(size: 13, weight: .regular)
    }

    public static func caption() -> Font {
        .system(size: 12, weight: .regular)
    }

    public static func label() -> Font {
        .system(size: 11, weight: .semibold)
    }

    public static func micro() -> Font {
        .system(size: 10, weight: .medium)
    }
}

public enum EISpacing {
    public static let unit: CGFloat = 4
    public static let cardPadding: CGFloat = 16
    public static let cardPaddingLarge: CGFloat = 24
    public static let cardGap: CGFloat = 8
    public static let sectionGap: CGFloat = 24
    public static let sidebarPadding: CGFloat = 20
    public static let detailPadding: CGFloat = 28
}

public enum EIRadius {
    public static let sm: CGFloat = 6
    public static let md: CGFloat = 10
    public static let lg: CGFloat = 14
    public static let xl: CGFloat = 16
    public static let pill: CGFloat = 20
    public static let widget: CGFloat = 22
    public static let full: CGFloat = 9999
}

public enum EILayout {
    public static let sidebarWidth: CGFloat = 240
    public static let contentWidth: CGFloat = 380
    public static let minAppWidth: CGFloat = 1024

    public enum Widget {
        public static let smallSize = CGSize(width: 170, height: 170)
        public static let mediumSize = CGSize(width: 364, height: 170)
        public static let largeSize = CGSize(width: 364, height: 382)
    }
}
