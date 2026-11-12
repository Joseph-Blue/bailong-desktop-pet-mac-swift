import AppKit

// GitHub mark: https://github.com/primer/octicons/blob/main/icons/mark-github-16.svg
// MIT License — Copyright (c) 2026 GitHub Inc.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
enum GitIcons {
    static let license = """
    MIT License — Copyright (c) 2026 GitHub Inc.
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
    static let lucideLicense = """
    ISC License — Copyright (c) 2026 Lucide Icons and Contributors
    Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
    THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
    """
    // Lucide git-branch: https://lucide.dev/icons/git-branch (ISC, notice above).
    // SVG's 24-point geometry, round caps and joins; scaled to a native template.
    static let git:NSImage = {
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            let path = NSBezierPath()
            path.move(to:NSPoint(x:15,y:6))
            path.curve(to:NSPoint(x:6,y:15),controlPoint1:NSPoint(x:10.029437,y:6),controlPoint2:NSPoint(x:6,y:10.029437))
            path.line(to:NSPoint(x:6,y:3))
            path.appendOval(in:NSRect(x:15,y:3,width:6,height:6))
            path.appendOval(in:NSRect(x:3,y:15,width:6,height:6))
            let transform = AffineTransform(scale:2.0/3.0)
            path.transform(using:transform)
            path.lineWidth = 4.0/3.0; path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.black.setStroke(); path.stroke(); return true
        }
        image.isTemplate = true; image.accessibilityDescription = "Git"; return image
    }()
    static let github:NSImage = {
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            let p = NSBezierPath()
            p.move(to:NSPoint(x:6.766000,y:11.328000))
            p.curve(to:NSPoint(x:3.250000,y:7.672000),controlPoint1:NSPoint(x:4.703000,y:11.078000),controlPoint2:NSPoint(x:3.250000,y:9.594000))
            p.curve(to:NSPoint(x:4.000000,y:5.484000),controlPoint1:NSPoint(x:3.250000,y:6.891000),controlPoint2:NSPoint(x:3.531000,y:6.047000))
            p.curve(to:NSPoint(x:4.063000,y:3.422000),controlPoint1:NSPoint(x:3.797000,y:4.969000),controlPoint2:NSPoint(x:3.828000,y:3.875000))
            p.curve(to:NSPoint(x:6.031000,y:4.125000),controlPoint1:NSPoint(x:4.688000,y:3.344000),controlPoint2:NSPoint(x:5.531000,y:3.672000))
            p.curve(to:NSPoint(x:8.016000,y:3.844000),controlPoint1:NSPoint(x:6.625000,y:3.938000),controlPoint2:NSPoint(x:7.250000,y:3.844000))
            p.curve(to:NSPoint(x:9.969000,y:4.109000),controlPoint1:NSPoint(x:8.781000,y:3.844000),controlPoint2:NSPoint(x:9.406000,y:3.938000))
            p.curve(to:NSPoint(x:11.938000,y:3.422000),controlPoint1:NSPoint(x:10.453000,y:3.672000),controlPoint2:NSPoint(x:11.313000,y:3.344000))
            p.curve(to:NSPoint(x:11.984000,y:5.469000),controlPoint1:NSPoint(x:12.156000,y:3.844000),controlPoint2:NSPoint(x:12.188000,y:4.937000))
            p.curve(to:NSPoint(x:12.750000,y:7.672000),controlPoint1:NSPoint(x:12.484000,y:6.062000),controlPoint2:NSPoint(x:12.750000,y:6.859000))
            p.curve(to:NSPoint(x:9.203000,y:11.312000),controlPoint1:NSPoint(x:12.750000,y:9.594000),controlPoint2:NSPoint(x:11.297000,y:11.047000))
            p.curve(to:NSPoint(x:10.093000,y:13.266000),controlPoint1:NSPoint(x:9.734000,y:11.656000),controlPoint2:NSPoint(x:10.093000,y:12.406000))
            p.line(to:NSPoint(x:10.093000,y:14.891000))
            p.curve(to:NSPoint(x:10.953000,y:15.438000),controlPoint1:NSPoint(x:10.093000,y:15.359000),controlPoint2:NSPoint(x:10.484000,y:15.625000))
            p.curve(to:NSPoint(x:16.000000,y:8.030000),controlPoint1:NSPoint(x:13.781000,y:14.359000),controlPoint2:NSPoint(x:16.000000,y:11.530000))
            p.curve(to:NSPoint(x:7.984000,y:0.000000),controlPoint1:NSPoint(x:16.000000,y:3.610000),controlPoint2:NSPoint(x:12.406000,y:0.000000))
            p.curve(to:NSPoint(x:0.000000,y:8.031000),controlPoint1:NSPoint(x:3.563000,y:0.000000),controlPoint2:NSPoint(x:0.000000,y:3.610000))
            p.curve(to:NSPoint(x:5.172000,y:15.453000),controlPoint1:NSPoint(x:-0.009220,y:11.346744),controlPoint2:NSPoint(x:2.058182,y:14.313537))
            p.curve(to:NSPoint(x:6.000000,y:14.906000),controlPoint1:NSPoint(x:5.594000,y:15.609000),controlPoint2:NSPoint(x:6.000000,y:15.328000))
            p.line(to:NSPoint(x:6.000000,y:13.656000))
            p.curve(to:NSPoint(x:5.250000,y:13.812000),controlPoint1:NSPoint(x:5.781000,y:13.750000),controlPoint2:NSPoint(x:5.500000,y:13.812000))
            p.curve(to:NSPoint(x:3.172000,y:12.203000),controlPoint1:NSPoint(x:4.219000,y:13.812000),controlPoint2:NSPoint(x:3.610000,y:13.250000))
            p.curve(to:NSPoint(x:2.453000,y:11.484000),controlPoint1:NSPoint(x:3.000000,y:11.781000),controlPoint2:NSPoint(x:2.812000,y:11.531000))
            p.curve(to:NSPoint(x:2.203000,y:11.297000),controlPoint1:NSPoint(x:2.266000,y:11.469000),controlPoint2:NSPoint(x:2.203000,y:11.391000))
            p.curve(to:NSPoint(x:2.828000,y:10.969000),controlPoint1:NSPoint(x:2.203000,y:11.109000),controlPoint2:NSPoint(x:2.516000,y:10.969000))
            p.curve(to:NSPoint(x:4.078000,y:11.829000),controlPoint1:NSPoint(x:3.281000,y:10.969000),controlPoint2:NSPoint(x:3.672000,y:11.250000))
            p.curve(to:NSPoint(x:5.109000,y:12.484000),controlPoint1:NSPoint(x:4.391000,y:12.281000),controlPoint2:NSPoint(x:4.718000,y:12.484000))
            p.curve(to:NSPoint(x:6.109000,y:11.984000),controlPoint1:NSPoint(x:5.500000,y:12.484000),controlPoint2:NSPoint(x:5.750000,y:12.344000))
            p.curve(to:NSPoint(x:6.766000,y:11.328000),controlPoint1:NSPoint(x:6.375000,y:11.719000),controlPoint2:NSPoint(x:6.579000,y:11.484000))
            p.close(); NSColor.black.setFill(); p.fill(); return true
        }
        image.isTemplate = true; image.accessibilityDescription = "GitHub"; return image
    }()
}
