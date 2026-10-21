// Draws the Stint icon (same design as stint.ico) as a macOS .iconset.
// Usage: makeicon <out.iconset>   then: iconutil -c icns <out.iconset>
#import <Cocoa/Cocoa.h>

static CGColorRef C(unsigned rgb) {
    return CGColorCreateSRGB(((rgb >> 16) & 255) / 255.0, ((rgb >> 8) & 255) / 255.0, (rgb & 255) / 255.0, 1);
}

static void Draw(CGContextRef g, CGFloat n) {
    // macOS icon grid: 824/1024 body, centred, ~185/1024 corner radius
    CGFloat side = n * 824 / 1024, o = (n - side) / 2, k = side / 256;  // k maps stint.ico's 256 px design
    CGRect body = CGRectMake(o, o, side, side);
    CGPathRef p = CGPathCreateWithRoundedRect(body, n * 185 / 1024, n * 185 / 1024, NULL);
    if (n >= 64) {
        CGColorRef sh = CGColorCreateSRGB(0, 0, 0, 0.3);
        CGContextSetShadowWithColor(g, CGSizeMake(0, -n * 10 / 1024), n * 20 / 1024, sh);
        CGColorRelease(sh);
    }
    CGColorRef bg = C(0x141924);
    CGContextSetFillColorWithColor(g, bg); CGContextAddPath(g, p); CGContextFillPath(g);
    CGContextSetShadowWithColor(g, CGSizeZero, 0, NULL);
    CGPathRelease(p); CGColorRelease(bg);

    // ring: outer r 77, inner r 49 (stroke centred at 63, width 28); top-left quadrant dim
    CGFloat cx = n / 2, cy = n / 2, r = 63 * k;
    CGContextSetLineWidth(g, 28 * k);
    CGColorRef dark = C(0x1C3A6B), light = C(0x2D8CFF), white = C(0xFFFFFF);
    CGContextSetStrokeColorWithColor(g, dark);
    CGContextAddArc(g, cx, cy, r, M_PI / 2, M_PI, 0); CGContextStrokePath(g);           // y-up: top -> left
    CGContextSetStrokeColorWithColor(g, light);
    CGContextAddArc(g, cx, cy, r, M_PI, 2.5 * M_PI, 0); CGContextStrokePath(g);         // left -> bottom -> right -> top
    CGContextSetFillColorWithColor(g, white);
    CGFloat d = 23.5 * k;
    CGContextFillEllipseInRect(g, CGRectMake(cx - d, cy - d, 2 * d, 2 * d));
    CGColorRelease(dark); CGColorRelease(light); CGColorRelease(white);
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: makeicon <out.iconset>\n"); return 1; }
        NSString* dir = [NSString stringWithUTF8String:argv[1]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        int sizes[] = {16, 32, 128, 256, 512};
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        for (int i = 0; i < 5; i++) {
            for (int scale = 1; scale <= 2; scale++) {
                int px = sizes[i] * scale;
                CGContextRef g = CGBitmapContextCreate(NULL, px, px, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
                Draw(g, px);
                CGImageRef img = CGBitmapContextCreateImage(g);
                NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
                NSString* name = scale == 1 ? [NSString stringWithFormat:@"icon_%dx%d.png", sizes[i], sizes[i]]
                                            : [NSString stringWithFormat:@"icon_%dx%d@2x.png", sizes[i], sizes[i]];
                NSData* png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                if (![png writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES]) {
                    fprintf(stderr, "makeicon: cannot write %s\n", name.UTF8String); return 1;
                }
                CGImageRelease(img); CGContextRelease(g);
            }
        }
        CGColorSpaceRelease(cs);
    }
    return 0;
}
