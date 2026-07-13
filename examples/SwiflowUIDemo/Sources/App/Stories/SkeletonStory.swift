import Swiflow
import SwiflowUI

@Component
final class SkeletonStory {
    var body: VNode {
        storyPage("Skeleton",
                  blurb: "A stateless shimmering placeholder — Badge's shape (a skinned span) for "
                       + "content that hasn't loaded yet. Purely decorative (aria-hidden) since the "
                       + "real content supplies the accessible semantics once it mounts. The shimmer "
                       + "gates on --sw-anim-play, so prefers-reduced-motion freezes it into a static "
                       + "block for free — no per-component code (the Spinner precedent).") {
            variantSection("Loading card", snippet: """
            HStack(spacing: .md, align: .center) {
                Skeleton(width: "2.5em", height: "2.5em", radius: "50%")
                VStack(spacing: .xs, align: .stretch) {
                    Skeleton(width: "60%")
                    Skeleton(width: "40%")
                }
            }
            """) {
                HStack(spacing: .md, align: .center) {
                    Skeleton(width: "2.5em", height: "2.5em", radius: "50%")
                    VStack(spacing: .xs, align: .stretch) {
                        Skeleton(width: "60%")
                        Skeleton(width: "40%")
                    }
                }
            }
            variantSection("Text lines", snippet: """
            Skeleton(lines: 3)   // a paragraph-shaped placeholder; the sheet shortens the last line
            """) {
                Skeleton(lines: 3)
            }
        }
    }
}
