# Subsets Inter to the characters Stint uses, makes digits tabular (so the
# timer doesn't wobble), and gives each weight its own family name so the app
# loads each one directly, without synthetic bolding.
import sys
from fontTools.ttLib import TTFont
from fontTools import subset

src = sys.argv[1]
jobs = [
    ("InterDisplay-Bold.ttf", "StintInterTime"),
    ("Inter-SemiBold.ttf", "StintInterSemi"),
    ("Inter-Regular.ttf", "StintInterBody"),
]
text = "".join(chr(c) for c in range(0x20, 0x7F)) + "·×—−…✓’"

def freeze_tnum(f):
    cmap = f.getBestCmap()
    gsub = f["GSUB"].table
    lookups = set()
    for fr in gsub.FeatureList.FeatureRecord:
        if fr.FeatureTag == "tnum":
            lookups.update(fr.Feature.LookupListIndex)
    mapping = {}
    for li in lookups:
        for st in gsub.LookupList.Lookup[li].SubTable:
            if hasattr(st, "ExtSubTable"):
                st = st.ExtSubTable
            if hasattr(st, "mapping"):
                mapping.update(st.mapping)
    for cp in list(range(0x30, 0x3A)) + [0x3A, 0x2B]:
        g = cmap.get(cp)
        if g in mapping:
            for t in f["cmap"].tables:
                if cp in t.cmap:
                    t.cmap[cp] = mapping[g]

for fn, fam in jobs:
    f = TTFont(f"{src}/{fn}")
    freeze_tnum(f)
    opts = subset.Options()
    opts.layout_features = ["kern"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    s = subset.Subsetter(opts)
    s.populate(text=text)
    s.subset(f)
    name = f["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 2, 4, 6, 16, 17, 21, 22):
            name.removeNames(nameID=rec.nameID)
    for nid, val in ((1, fam), (2, "Regular"), (4, fam), (6, fam), (16, fam), (17, "Regular")):
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    f["OS/2"].fsSelection = (f["OS/2"].fsSelection & ~0b1100001) | 0b1000000  # REGULAR
    f["head"].macStyle = 0
    out = f"fonts/{fam}.ttf"
    f.save(out)
    print(out)
