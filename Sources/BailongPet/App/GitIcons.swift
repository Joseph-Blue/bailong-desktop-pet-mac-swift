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
    // Git official black logomark by Jason Long, CC BY 3.0.
    // https://git-scm.com/community/logos · https://creativecommons.org/licenses/by/3.0/
    // Original SVG path transformed into native template coordinates; geometry unchanged.
    static let git:NSImage = {
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            let p = NSBezierPath()
            p.move(to:NSPoint(x:8.725238,y:15.687520))
            p.curve(to:NSPoint(x:7.274762,y:15.687520),controlPoint1:NSPoint(x:8.324701,y:16.088057),controlPoint2:NSPoint(x:7.675299,y:16.088057))
            p.line(to:NSPoint(x:0.312480,y:8.725238))
            p.curve(to:NSPoint(x:0.312480,y:7.274762),controlPoint1:NSPoint(x:-0.088057,y:8.324701),controlPoint2:NSPoint(x:-0.088057,y:7.675299))
            p.line(to:NSPoint(x:5.099049,y:2.488193))
            p.line(to:NSPoint(x:6.918531,y:4.307675))
            p.curve(to:NSPoint(x:7.202239,y:5.606716),controlPoint1:NSPoint(x:6.756438,y:4.744782),controlPoint2:NSPoint(x:6.851006,y:5.255483))
            p.curve(to:NSPoint(x:7.559702,y:5.855640),controlPoint1:NSPoint(x:7.308869,y:5.713346),controlPoint2:NSPoint(x:7.430198,y:5.796322))
            p.line(to:NSPoint(x:7.559702,y:10.289407))
            p.curve(to:NSPoint(x:7.202239,y:10.538332),controlPoint1:NSPoint(x:7.430198,y:10.348726),controlPoint2:NSPoint(x:7.308869,y:10.431702))
            p.curve(to:NSPoint(x:7.202239,y:12.278903),controlPoint1:NSPoint(x:6.721593,y:11.018978),controlPoint2:NSPoint(x:6.721593,y:11.798257))
            p.curve(to:NSPoint(x:8.942809,y:12.278903),controlPoint1:NSPoint(x:7.682884,y:12.759548),controlPoint2:NSPoint(x:8.462164,y:12.759548))
            p.curve(to:NSPoint(x:8.942809,y:10.538332),controlPoint1:NSPoint(x:9.423455,y:11.798257),controlPoint2:NSPoint(x:9.423455,y:11.018978))
            p.curve(to:NSPoint(x:8.585345,y:10.289407),controlPoint1:NSPoint(x:8.836179,y:10.431702),controlPoint2:NSPoint(x:8.714849,y:10.348726))
            p.line(to:NSPoint(x:8.585345,y:5.974489))
            p.line(to:NSPoint(x:10.254626,y:7.643770))
            p.curve(to:NSPoint(x:10.538333,y:8.942810),controlPoint1:NSPoint(x:10.092533,y:8.080877),controlPoint2:NSPoint(x:10.187101,y:8.591578))
            p.curve(to:NSPoint(x:12.278904,y:8.942810),controlPoint1:NSPoint(x:11.018979,y:9.423456),controlPoint2:NSPoint(x:11.798259,y:9.423456))
            p.curve(to:NSPoint(x:12.278904,y:7.202240),controlPoint1:NSPoint(x:12.759550,y:8.462165),controlPoint2:NSPoint(x:12.759550,y:7.682885))
            p.curve(to:NSPoint(x:10.979864,y:6.918533),controlPoint1:NSPoint(x:11.927673,y:6.851009),controlPoint2:NSPoint(x:11.416971,y:6.756439))
            p.line(to:NSPoint(x:9.226518,y:5.165186))
            p.curve(to:NSPoint(x:8.942810,y:3.866146),controlPoint1:NSPoint(x:9.388611,y:4.728080),controlPoint2:NSPoint(x:9.294043,y:4.217379))
            p.curve(to:NSPoint(x:7.643770,y:3.582439),controlPoint1:NSPoint(x:8.591579,y:3.514915),controlPoint2:NSPoint(x:8.080877,y:3.420346))
            p.line(to:NSPoint(x:5.824288,y:1.762957))
            p.line(to:NSPoint(x:7.274764,y:0.312482))
            p.curve(to:NSPoint(x:8.725239,y:0.312482),controlPoint1:NSPoint(x:7.675301,y:-0.088056),controlPoint2:NSPoint(x:8.324702,y:-0.088056))
            p.line(to:NSPoint(x:15.687521,y:7.274764))
            p.curve(to:NSPoint(x:15.687521,y:8.725239),controlPoint1:NSPoint(x:16.088059,y:7.675301),controlPoint2:NSPoint(x:16.088059,y:8.324702))
            p.close()
            NSColor.black.setFill(); p.fill(); return true
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
