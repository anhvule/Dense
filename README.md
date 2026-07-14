# Dense

Dense is a native macOS app that compresses videos and PDFs, sized for where they're going.

## Features

- **Destination-driven compression**: Choose a sidebar preset (Discord ≤25 MB, Slack ≤50 MB, Email ≤10 MB, Email ≤25 MB, Web/Social, YouTube, or Custom), drop your files, and go. Selection persists across launches.

- **Video compression**: Hardware-accelerated H.264/HEVC encoding via VideoToolbox. Batch processing, video-to-GIF conversion, and target-size mode to fit your destination's byte budget.

- **PDF compression**: Fit-to-email target sizes (10 MB, 25 MB) with an adaptive quality ladder—walks down Good → Balanced → Small to stay under the budget while keeping text legible.

- **Preview inspector**: Side-by-side comparison of original vs. compressed. Adjust a target-size slider (video) or pick a quality tier (PDF) before committing. Live rendering on every change.

- **Batch safety**: Originals are never touched; outputs get a `-compressed` suffix. Drop whole folders; one corrupted or unsupported file won't abort the batch.

- **Robust error handling**: Junk files, password-protected PDFs, vector-only documents, and extreme quality targets fail gracefully with clear feedback and don't stall the queue.