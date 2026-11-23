"""Local contour antialiasing on cleaned RGBA frames; no uniform stroke."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter


def near(mask):
    return np.asarray(Image.fromarray(mask.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3))) > 0


def gaussian(values, sigma=0.65):
    weights = np.exp(-np.arange(-2, 3, dtype=np.float32)**2/(2*sigma*sigma))
    weights /= weights.sum()
    h, w = values.shape[:2]
    pad = ((2, 2), (2, 2)) + ((0, 0),)*(values.ndim-2)
    padded = np.pad(values, pad, mode='edge')
    horizontal = sum(float(k)*padded[2:2+h, i:i+w] for i, k in enumerate(weights))
    padded = np.pad(horizontal, ((2, 2), (0, 0))+((0, 0),)*(values.ndim-2), mode='edge')
    return sum(float(k)*padded[i:i+h] for i, k in enumerate(weights))


def smooth(rgba):
    alpha = rgba[:, :, 3].astype(np.float32)/255
    visible = alpha > 0
    transparent = ~visible
    # Only the immediate contour neighborhood, including internal hair holes.
    band = near(visible) & near(transparent)
    blurred = gaussian(alpha)
    target = np.clip((blurred-0.06)/0.88, 0, 1)
    target[transparent] = np.minimum(target[transparent], 96/255)
    result = rgba.copy()
    result[:, :, 3][band] = np.rint(target[band]*255).astype(np.uint8)
    added = transparent & (result[:, :, 3] > 0)
    if added.any():
        # Only accepted v2 pixels contribute; alpha-zero RGB can contain garbage.
        premultiplied = rgba[:, :, :3].astype(np.float32)*alpha[:, :, None]
        colors = gaussian(premultiplied)
        result[:, :, :3][added] = np.clip(np.rint(colors[added]/blurred[added, None]), 0, 255).astype(np.uint8)
    changed = np.any(result != rgba, axis=2)
    assert not (changed & ~band).any()
    assert not (added & ~near(visible)).any()
    assert np.array_equal(result[:, :, :3][visible], rgba[:, :, :3][visible])
    assert np.array_equal(result[~band], rgba[~band])
    stats = {
        'changed_pixels': int(changed.sum()),
        'added_antialias_pixels': int(added.sum()),
        'removed_pixels': int((visible & (result[:, :, 3] == 0)).sum()),
        'alpha_area_before': float(alpha.sum()),
        'alpha_area_after': float(result[:, :, 3].sum()/255),
        'max_added_alpha': int(result[:, :, 3][added].max()) if added.any() else 0,
        'changed_outside_band': 0,
        'existing_visible_rgb_changed': 0,
    }
    # Review map: green = increased alpha, red = reduced alpha, dark = unchanged.
    delta = result[:, :, 3].astype(np.int16)-rgba[:, :, 3].astype(np.int16)
    mask = np.zeros_like(rgba[:, :, :3])
    mask[:, :, 0] = np.clip(-delta*3, 0, 255)
    mask[:, :, 1] = np.clip(delta*3, 0, 255)
    return result, mask, stats


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--batch', type=Path, required=True)
    parser.add_argument('--samples', action='store_true')
    args = parser.parse_args()
    root = args.batch.resolve()
    output = root/('sample-repaired' if args.samples else 'repaired')
    masks = root/('sample-masks' if args.samples else 'masks')
    reports = []
    for folder in sorted(p for p in (root/'originals').iterdir() if p.is_dir()):
        frames = sorted(folder.glob('*.png'))
        if args.samples:
            frames = [p for p in frames if p.name in {'0001.png', '0048.png', '0096.png'}]
        if not frames:
            raise ValueError(f'No frames: {folder}')
        dest = output/folder.name
        dest.mkdir(parents=True, exist_ok=False)
        maskdest = masks/folder.name
        maskdest.mkdir(parents=True, exist_ok=False)
        rows = []
        for i, path in enumerate(frames, 1):
            with Image.open(path) as im:
                if im.mode != 'RGBA':
                    raise ValueError(f'Expected RGBA: {path}')
                source = np.array(im)
            fixed, mask, stats = smooth(source)
            Image.fromarray(fixed).save(dest/path.name)
            Image.fromarray(mask).save(maskdest/path.name)
            with Image.open(dest/path.name) as saved:
                if saved.mode != 'RGBA' or not np.array_equal(np.array(saved), fixed):
                    raise ValueError(f'PNG round-trip failed: {path}')
                if saved.getchannel('A').getextrema()[0] != 0:
                    raise ValueError(f'No transparent background: {path}')
            rows.append({'frame': path.name, **stats})
            if i % 24 == 0 or i == len(frames):
                print(f'{folder.name}: {i}/{len(frames)}', flush=True)
        reports.append({'folder': folder.name, 'frames': len(frames), 'details': rows})
    (root/('sample-report.json' if args.samples else 'smooth-report.json')).write_text(
        json.dumps(reports, ensure_ascii=False, indent=2)+'\n')
    print('Smoothing completed: '+str(root), flush=True)


if __name__ == '__main__':
    main()
