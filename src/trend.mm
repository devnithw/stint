// Focus trend: focused time per day, and the week view that charts it.
// Included by stint.mm (it shares that file's state and drawing helpers); not compiled on its own.

// ---------------------------------------------------------------- data
// Focused milliseconds per local calendar day, keyed yyyymmdd.
// Stored with NSUserDefaults under "focusDays" as {"20261021": ms}.
static std::map<int, long long> gDays;
static bool gDaysLoaded = false, gDaysDirty = false;
static unsigned long long gDaysSaved = 0;

static int DayKey(time_t t) {
    struct tm tm; localtime_r(&t, &tm);
    return (tm.tm_year + 1900) * 10000 + (tm.tm_mon + 1) * 100 + tm.tm_mday;
}
static int TodayIndex() {  // 0 = Monday
    time_t now = time(nullptr); struct tm t; localtime_r(&now, &t);
    return (t.tm_wday + 6) % 7;
}

static void TrendLoad() {
    if (gDaysLoaded) return;
    gDaysLoaded = true;
    NSDictionary* d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"focusDays"];
    for (NSString* k in d) {
        id v = d[k];
        if ([k isKindOfClass:[NSString class]] && k.intValue > 0 && [v respondsToSelector:@selector(longLongValue)])
            gDays[k.intValue] = max(0LL, [v longLongValue]);
    }
}
static void TrendSave() {
    if (!gDaysDirty) return;
    NSMutableDictionary* d = [NSMutableDictionary dictionary];
    for (auto& [k, v] : gDays) d[[NSString stringWithFormat:@"%d", k]] = @(v);
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:@"focusDays"];
    gDaysDirty = false; gDaysSaved = Now();
}
// Called from Tick with the focus time that just passed.
static void TrendAdd(long long ms) {
    if (ms <= 0) return;
    TrendLoad();
    gDays[DayKey(time(nullptr))] += ms;
    gDaysDirty = true;
    if (Now() - gDaysSaved > 30000) TrendSave();  // a crash loses at most ~30 s
}

struct Week { int key[7]; long long day[7]; long long total; };
// The week `back` weeks ago (0 = this week), Monday first.
static Week WeekOf(int back) {
    TrendLoad();
    time_t now = time(nullptr); struct tm t; localtime_r(&now, &t);
    int fromMon = (t.tm_wday + 6) % 7;
    Week w{};
    for (int i = 0; i < 7; i++) {
        struct tm d = t;
        d.tm_mday += i - fromMon - 7 * back;
        d.tm_hour = 12; d.tm_min = d.tm_sec = 0; d.tm_isdst = -1;  // midday steers clear of DST jumps
        w.key[i] = DayKey(mktime(&d));
        auto it = gDays.find(w.key[i]);
        w.day[i] = it == gDays.end() ? 0 : it->second;
        w.total += w.day[i];
    }
    return w;
}

// ---------------------------------------------------------------- drawing
// Monotone cubic through the points: smooth, but never overshoots (so it never dips below zero).
static CGMutablePathRef SmoothPath(const CGPoint* pt, int n) {
    CGMutablePathRef p = CGPathCreateMutable();
    if (n < 1) return p;
    CGPathMoveToPoint(p, nullptr, pt[0].x, pt[0].y);
    if (n == 1) return p;
    std::vector<CGFloat> d(n - 1), m(n);
    for (int i = 0; i < n - 1; i++) d[i] = (pt[i + 1].y - pt[i].y) / (pt[i + 1].x - pt[i].x);
    m[0] = d[0]; m[n - 1] = d[n - 2];
    for (int i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
    for (int i = 0; i < n - 1; i++) {  // Fritsch–Carlson limiter
        if (d[i] == 0) { m[i] = m[i + 1] = 0; continue; }
        CGFloat a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
        if (s > 9) { CGFloat k = 3 / sqrt(s); m[i] = k * a * d[i]; m[i + 1] = k * b * d[i]; }
    }
    for (int i = 0; i < n - 1; i++) {
        CGFloat h = (pt[i + 1].x - pt[i].x) / 3;
        CGPathAddCurveToPoint(p, nullptr, pt[i].x + h, pt[i].y + m[i] * h,
                              pt[i + 1].x - h, pt[i + 1].y - m[i + 1] * h, pt[i + 1].x, pt[i + 1].y);
    }
    return p;
}
static void StrokePath(CGPathRef p, Col c, CGFloat lw) {
    CGContextBeginPath(G); CGContextAddPath(G, p); SetStroke(c, lw, true); CGContextStrokePath(G);
}

// This week (solid, filled) over last week (dashed), one point per day.
static void DrawChart(const Week& cur, const Week& prev, int today, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    long long peak = 0;
    for (int i = 0; i < 7; i++) { peak = max(peak, prev.day[i]); if (i <= today) peak = max(peak, cur.day[i]); }
    const long long HR = 3600000;
    long long top = max(1LL, (peak + HR - 1) / HR) * HR;  // whole hours, at least 1h

    for (int g = 0; g <= 2; g++) {
        CGFloat gy = y + h - h * g / 2 + 0.5;
        Line(ARGB(g ? 16 : 32, 255, 255, 255), 1, x, gy, x + w, gy);
    }
    Text(ShortDur(top / 60000), 2, 10, x + w, y - 5, P::dim, AL_R);

    auto at = [&](int i, long long v) { return CGPointMake(x + w * i / 6, y + h - h * (CGFloat)v / top); };
    CGPoint pp[7], cp[7];
    for (int i = 0; i < 7; i++) { pp[i] = at(i, prev.day[i]); cp[i] = at(i, cur.day[i]); }

    CGMutablePathRef last = SmoothPath(pp, 7);
    CGContextSaveGState(G);
    CGFloat dash[2] = {3, 4};
    CGContextSetLineDash(G, 0, dash, 2);
    StrokePath(last, Hex(0x5A6680), 1.5);
    CGContextRestoreGState(G);
    CGPathRelease(last);

    int n = today + 1;
    CGMutablePathRef line = SmoothPath(cp, n);
    if (n > 1) {  // soft fill under this week's line
        CGMutablePathRef area = CGPathCreateMutableCopy(line);
        CGPathAddLineToPoint(area, nullptr, cp[n - 1].x, y + h);
        CGPathAddLineToPoint(area, nullptr, cp[0].x, y + h);
        CGPathCloseSubpath(area);
        CGContextSaveGState(G);
        CGContextBeginPath(G); CGContextAddPath(G, area); CGContextClip(G);
        Col b = P::blue;
        CGFloat comps[8] = {b.r, b.g, b.b, 0.34, b.r, b.g, b.b, 0}, pos[2] = {0, 1};
        CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGGradientRef gr = CGGradientCreateWithColorComponents(cs, comps, pos, 2);
        CGContextDrawLinearGradient(G, gr, CGPointMake(0, y), CGPointMake(0, y + h), 0);
        CGGradientRelease(gr); CGColorSpaceRelease(cs);
        CGContextRestoreGState(G);
        CGPathRelease(area);
        StrokePath(line, P::blue, 2.2);
    }
    CGPathRelease(line);
    CGPoint d = cp[today];  // today's point
    FillEllipse(P::blue, d.x - 5, d.y - 5, 10, 10);
    FillEllipse(P::text, d.x - 2.5, d.y - 2.5, 5, 5);

    const char* lab = "MTWTFSS";
    for (int i = 0; i < 7; i++)
        Text([NSString stringWithFormat:@"%c", lab[i]], i == today ? 1 : 2, 11, at(i, 0).x, y + h + 17,
             i == today ? P::text : P::dim, AL_C);
}

static void DrawTrend(CGFloat W, CGFloat H) {
    DrawCard(W, H, 26);
    Week cur = WeekOf(0), prev = WeekOf(1);
    int today = TodayIndex();

    static const char* months[12] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    int mk = cur.key[0];
    Text(@"This week", 1, 18, 20, 40, P::text);
    Text([NSString stringWithFormat:@"Week of %s %d", months[(mk / 100) % 100 - 1], mk % 100], 2, 12, 20, 58, P::sub);
    IconButton(Z_BACK, 8, W - 20 - 9, 34);

    // weekly total, and the change against the same days last week
    long long same = 0;
    for (int i = 0; i <= today; i++) same += prev.day[i];
    long long dm = (cur.total - same) / 60000;
    NSString* ds = dm == 0 ? @"Even" : [(dm > 0 ? @"+" : @"−") stringByAppendingString:ShortDur(llabs(dm))];
    NSString* vs = today == 6 ? @"vs last week" : @"vs this time last week";
    CGFloat dw = max(TextW(ds, 1, 14), TextW(vs, 2, 11.5));
    NSString* tot = ShortDur(cur.total / 60000);
    CGFloat ts = 34;
    while (ts > 22 && 19 + TextW(tot, 0, ts) > W - 20 - dw - 12) ts -= 2;
    Text(tot, 0, ts, 19, 104, P::text);
    Text(ds, 1, 14, W - 20, 86, dm > 0 ? P::blueText : P::soft, AL_R);
    Text(vs, 2, 11.5, W - 20, 103, P::dim, AL_R);

    DrawChart(cur, prev, today, 20, 134, W - 40, 82);

    // legend
    CGFloat lx = 20, ly = 256;
    Line(P::blue, 2.2, lx, ly - 4, lx + 14, ly - 4, true);
    lx += 20 + Text(@"This week", 2, 11.5, lx + 20, ly, P::sub) + 16;
    CGContextSaveGState(G);
    CGFloat dash[2] = {3, 3};
    CGContextSetLineDash(G, 0, dash, 2);
    Line(Hex(0x5A6680), 1.5, lx, ly - 4, lx + 14, ly - 4);
    CGContextRestoreGState(G);
    Text([@"Last week · " stringByAppendingString:ShortDur(prev.total / 60000)], 2, 11.5, lx + 20, ly, P::sub);

    Line(ARGB(18, 255, 255, 255), 1, 20, 272.5, W - 20, 272.5);

    // daily breakdown, Monday first
    static NSString* const names[7] = {@"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat", @"Sun"};
    long long best = 1;
    for (int i = 0; i < 7; i++) best = max(best, cur.day[i]);
    CGFloat bx = 58, bw = W - 20 - 62 - bx;
    for (int i = 0; i < 7; i++) {
        CGFloat cy = 292 + i * 20;
        bool now = i == today, future = i > today;
        Text(names[i], now ? 1 : 2, 12.5, 20, cy + 4.5, now ? P::text : future ? P::dim : P::soft);
        FillRR(Hex(0x1F2A40), bx, cy - 3, bw, 6, 3);
        if (!future && cur.day[i] > 0) FillRR(now ? P::blue : Hex(0x2563C8), bx, cy - 3, max(6.0, bw * cur.day[i] / best), 6, 3);
        NSString* v = future ? @"—" : ShortDur(cur.day[i] / 60000);
        Text(v, 1, 12, W - 20, cy + 4.5, now ? P::text : (future || !cur.day[i]) ? P::dim : P::soft, AL_R);
    }
}
