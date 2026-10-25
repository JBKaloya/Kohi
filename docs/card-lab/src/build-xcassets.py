# ./stickers-png/*.png (720 px) → ../OriginStickers.xcassets/Stickers/<name>.imageset (480 px, 256 colours).
#   pip install pillow
#   python3 build-xcassets.py
import glob, json, os, shutil
from PIL import Image
here = os.path.dirname(os.path.abspath(__file__))
catalog = os.path.join(here, '..', 'OriginStickers.xcassets')
ns = os.path.join(catalog, 'Stickers')
shutil.rmtree(catalog, ignore_errors=True)
os.makedirs(ns)
info = {"author": "xcode", "version": 1}
json.dump({"info": info}, open(os.path.join(catalog, 'Contents.json'), 'w'), indent=2)
json.dump({"info": info, "properties": {"provides-namespace": True}}, open(os.path.join(ns, 'Contents.json'), 'w'), indent=2)
files = sorted(glob.glob(os.path.join(here, 'stickers-png', '*.png')))
for f in files:
    name = os.path.basename(f)[:-4]
    d = os.path.join(ns, name + '.imageset'); os.makedirs(d)
    im = Image.open(f).convert('RGBA').resize((480, 480), Image.LANCZOS)
    im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(os.path.join(d, name + '.png'), optimize=True)
    json.dump({"images": [{"filename": name + '.png', "idiom": "universal"}], "info": info}, open(os.path.join(d, 'Contents.json'), 'w'), indent=2)
print(len(files), 'imagesets in', os.path.normpath(catalog))
