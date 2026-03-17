import SwiftUI
import Charts
import EddingsKit

struct MiniSparkline: View {
    let data: [Double]
    var color: Color = EIColor.emerald
    var height: CGFloat = 32

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Day", index),
                y: .value("Value", value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Day", index),
                y: .value("Value", value)
            )
            .foregroundStyle(color.opacity(0.1))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}
