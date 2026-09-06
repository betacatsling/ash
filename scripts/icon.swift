import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(red: 0.13, green: 0.15, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.07,y:s*0.07,width:s*0.86,height:s*0.86),xRadius:s*0.19,yRadius:s*0.19).fill()
    NSColor(red: 0.88,green:0.67,blue:0.42,alpha:1).setStroke()
    let mark=NSBezierPath(); mark.lineWidth=s*0.06; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
    mark.move(to: NSPoint(x:s*0.28,y:s*0.67)); mark.line(to:NSPoint(x:s*0.47,y:s*0.5)); mark.line(to:NSPoint(x:s*0.28,y:s*0.33)); mark.stroke()
    NSColor(red:0.89,green:0.91,blue:0.86,alpha:1).setStroke()
    let cursor=NSBezierPath(); cursor.lineWidth=s*0.055; cursor.lineCapStyle = .round
    cursor.move(to:NSPoint(x:s*0.56,y:s*0.34)); cursor.line(to:NSPoint(x:s*0.74,y:s*0.34)); cursor.stroke()
    image.unlockFocus()
    let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data=rep.representation(using:.png,properties:[:])!
    if [16,32,128,256,512].contains(size) { try data.write(to:URL(fileURLWithPath:"\(destination)/icon_\(size)x\(size).png")) }
    if [32,64,256,512,1024].contains(size) { try data.write(to:URL(fileURLWithPath:"\(destination)/icon_\(size/2)x\(size/2)@2x.png")) }
}
