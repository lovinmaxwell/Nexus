import SwiftUI

/// Detailed visualization of file segmentation showing active threads filling the file.
/// Animates progress for smooth real-time UX feedback.
struct DetailedSegmentationMapView: View {
    let segments: [FileSegment]
    let totalSize: Int64
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background (total file size)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: geometry.size.width)
                
                // Draw each segment with animated progress
                ForEach(segments) { segment in
                    let startRatio = totalSize > 0 ? CGFloat(segment.startOffset) / CGFloat(totalSize) : 0
                    let segmentWidth = totalSize > 0 ? CGFloat(segment.endOffset - segment.startOffset + 1) / CGFloat(totalSize) : 0
                    let progressRatio = totalSize > 0 ? CGFloat(segment.currentOffset - segment.startOffset) / CGFloat(totalSize) : 0
                    
                    // Segment background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.isComplete ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                        .frame(width: max(2, geometry.size.width * segmentWidth))
                        .offset(x: geometry.size.width * startRatio)
                    
                    // Progress within segment - animated for fluid UX
                    if progressRatio > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.isComplete ? Color.green : Color.blue)
                            .frame(width: max(2, geometry.size.width * progressRatio))
                            .offset(x: geometry.size.width * startRatio)
                            .animation(.easeOut(duration: 0.12), value: progressRatio)
                    }
                }
            }
        }
    }
}
