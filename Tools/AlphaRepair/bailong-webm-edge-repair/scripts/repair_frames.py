"""PNG alpha-only edge cleanup. Originals stay read-only; no generated artwork."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter


def dilate(mask, size=3):
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(size))) > 0


def connected_to_seeds(allowed, seeds):
    """Four-connected row spans: fill every allowed component with a transparent seed."""
    height, width = allowed.shape
    parents, touched, spans = [], [], []

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    previous = []
    for y in range(height):
        changes = np.diff(np.pad(allowed[y].astype(np.int8), (1, 1)))
        starts, ends = np.flatnonzero(changes == 1), np.flatnonzero(changes == -1)
        current = []
        cursor = 0
        for left, right in zip(starts.tolist(), ends.tolist()):
            label = len(parents)
            parents.append(label)
            touched.append(bool(seeds[y, left:right].any()))
            spans.append((y, left, right, label))
            while cursor < len(previous) and previous[cursor][1] <= left:
                cursor += 1
            j = cursor
            while j < len(previous) and previous[j][0] < right:
                a, b = find(label), find(previous[j][2])
                if a != b:
                    parents[b] = a
                    touched[a] = touched[a] or touched[b]
                j += 1
            current.append((left, right, label))
        previous = current
    result = np.zeros((height, width), dtype=bool)
    for y, left, right, label in spans:
        if touched[find(label)]:
            result[y, left:right] = True
    return result


def repair_conservative(rgba):
    color = rgba[:, :, :3].astype(np.float32)
    alpha = rgba[:, :, 3]
    r, g, b = color.transpose(2, 0, 1)
    high, low = color.max(axis=2), color.min(axis=2)
    # Channel differences cover blue-purple, violet and light desaturated purple.
    purple = (b-g >= 9) & (r-g >= -14) & (b-r >= -5) & (high-low >= 12)
    pale_purple = (b-g >= 4) & (r-g >= -16) & (b-r >= -7)
    strong_line = purple & (alpha >= 150)
    protected = (purple & (alpha >= 48)) | (pale_purple & (alpha >= 16) & dilate(strong_line))
    # Compression can desaturate individual outline pixels. Keep the immediate
    # one-pixel transition beside a solid purple line even if its hue is neutral.
    protected |= dilate(strong_line) & (alpha >= 48)

    # White hair/dress and skin are not color-keyed. Opaque areas form barriers.
    light_body = (high >= 204) & (b >= g-7)
    skin = (r-b >= 16) & (r-g >= 7) & (r >= 170) & (high-low >= 28)
    interior = (alpha >= 224) & (light_body | skin | purple)
    barrier = protected | interior

    # A family of neutral/warm/dull colors, rather than a single yellow-gray key.
    neutral_warm = ((high-low <= 46) & (b-g <= 11) & (b-r <= 9))
    dull = (high <= 180) & (high-low <= 65) & (b-g <= 13)
    candidate = (alpha < 224) | neutral_warm | dull
    exterior = connected_to_seeds((candidate & ~barrier) | (alpha == 0), alpha == 0)

    # Remove exterior junk; retain a narrow antialiased fringe adjacent to purple.
    adjacent = dilate(protected)
    faint_purple = pale_purple & adjacent & (alpha >= 8)
    remove = exterior & (alpha > 0) & ~protected & ~faint_purple
    result = rgba.copy()
    result[:, :, 3][remove] = 0
    # Do not repaint RGB or alter detected outline pixels, even at low opacity.
    assert np.array_equal(result[:, :, :3], rgba[:, :, :3])
    assert np.array_equal(result[protected], rgba[protected])
    report = {
        'visible_pixels_before': int((alpha > 0).sum()),
        'removed_pixels': int(remove.sum()),
        'removed_alpha_equivalent_pixels': float(alpha[remove].sum() / 255),
        'protected_pixels': int(protected.sum()),
        'protected_pixels_changed': 0,
        'rgb_pixels_changed': 0,
    }
    return result, remove, protected, report


def near(mask, radius):
    """Square neighborhood occupancy via integral image, without SciPy/OpenCV."""
    padded = np.pad(mask.astype(np.int32), radius)
    integral = np.pad(padded, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    n = 2*radius+1
    return (integral[n:, n:] - integral[:-n, n:] - integral[n:, :-n] + integral[:-n, :-n]) > 0


def repair_aggressive(rgba):
    color = rgba[:, :, :3].astype(np.float32)
    alpha = rgba[:, :, 3]
    r, g, b = color.transpose(2, 0, 1)
    high, low = color.max(axis=2), color.min(axis=2)
    # Protect solid ink, not an arbitrary whole ring around it. Weak purple is
    # eligible for cleanup, as explicitly authorized for this aggressive pass.
    ink = (((b-g >= 12) & (b-r >= 3) & (r-g >= -20)) |
           ((high < 145) & (b-g >= 7) & (b-r >= -4))) & (alpha >= 160)
    light_body = (alpha >= 236) & (high >= 195) & (b-g >= 4)
    skin = (alpha >= 224) & (r-b >= 18) & (r-g >= 12) & (r >= 160)
    barrier = ink | light_body | skin
    background = alpha <= 8

    # Route 1: external fringe and already-transparent holes.
    gray_family = (high < 218) & (high-low < 75) & (b-g < 16) & (b-r < 13)
    warm_family = (g >= r-14) & (g-b >= 2)
    allowed = ((alpha < 236) | gray_family | warm_family) & ~barrier
    exterior = connected_to_seeds(allowed | background, background)
    outer_remove = exterior & (alpha > 0) & ~barrier

    # Route 2: opaque olive/yellow-gray islands enclosed by curls. They need
    # their own seeds because some contain no transparent pixels at all.
    boundary_zone = near(background, 36)
    olive_seed = (g >= r-12) & (g-b >= 10) & (r-b >= 4) & (high < 225)
    olive_seed &= (alpha > 8) & boundary_zone & ~barrier
    pocket_family = (high < 228) & (g >= r-15) & (b-g <= 10) & (b-r <= 8)
    pocket_allowed = (pocket_family | (alpha < 176)) & ~barrier
    pockets = connected_to_seeds(pocket_allowed, olive_seed & pocket_allowed)
    pocket_remove = pockets & (alpha > 0)

    # Remove polluted one-pixel transitions around both cleanup routes. This
    # may thin weak outlines; no new outline pixels are drawn or dilated.
    border = near(outer_remove | pocket_remove, 1)
    fringe = border & ~barrier & (alpha > 0) & (
        (alpha < 192) | ((b-g < 16) & (b-r < 13) & (high < 218)))
    remove = outer_remove | pocket_remove | fringe
    result = rgba.copy()
    result[:, :, 3][remove] = 0
    assert np.array_equal(result[:, :, :3], rgba[:, :, :3])
    assert np.array_equal(result[barrier], rgba[barrier])
    report = {
        'algorithm': 'aggressive-v2',
        'visible_pixels_before': int((alpha > 0).sum()),
        'removed_pixels': int(remove.sum()),
        'removed_alpha_equivalent_pixels': float(alpha[remove].sum()/255),
        'outer_removed_pixels': int(outer_remove.sum()),
        'pocket_removed_pixels': int((pocket_remove & ~outer_remove).sum()),
        'transition_removed_pixels': int((fringe & ~(outer_remove | pocket_remove)).sum()),
        'pocket_seed_pixels': int(olive_seed.sum()),
        'protected_pixels': int(barrier.sum()),
        'protected_pixels_changed': 0,
        'rgb_pixels_changed': 0,
    }
    return result, remove, barrier, report, outer_remove, pocket_remove


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--batch', type=Path, required=True)
    parser.add_argument('--samples', action='store_true', help='Only 0001, 0048, 0096 in separate sample output')
    parser.add_argument('--mode', choices=['aggressive', 'conservative'], default='aggressive')
    args = parser.parse_args()
    batch = args.batch.resolve()
    original = batch/'originals'
    output = batch/('sample-repaired' if args.samples else 'repaired')
    masks = batch/('sample-masks' if args.samples else 'masks')
    groups = sorted(p for p in original.iterdir() if p.is_dir())
    if not groups:
        raise ValueError('No original frame folders')
    report = []
    for folder in groups:
        frames = sorted(folder.glob('*.png'))
        if args.samples:
            frames = [p for p in frames if p.name in {'0001.png', '0048.png', '0096.png'}]
        if not frames:
            raise ValueError(f'No PNGs in {folder}')
        destination, mask_folder = output/folder.name, masks/folder.name
        destination.mkdir(parents=True, exist_ok=False)
        mask_folder.mkdir(parents=True, exist_ok=False)
        summary = []
        for i, path in enumerate(frames, 1):
            with Image.open(path) as image:
                if image.mode != 'RGBA':
                    raise ValueError(f'{path} is not RGBA')
                rgba = np.array(image)
            if args.mode == 'aggressive':
                fixed, removed, protected, stats, outer, pockets = repair_aggressive(rgba)
                # Separate masks make the two cleanup routes reviewable.
                Image.fromarray(outer.astype(np.uint8)*255).save(mask_folder/(path.stem+'-outer.png'))
                Image.fromarray(pockets.astype(np.uint8)*255).save(mask_folder/(path.stem+'-pockets.png'))
            else:
                fixed, removed, protected, stats = repair_conservative(rgba)
            Image.fromarray(fixed).save(destination/path.name)
            Image.fromarray(removed.astype(np.uint8)*255).save(mask_folder/path.name)
            if path.name in {'0001.png', '0048.png', '0096.png'}:
                Image.fromarray(protected.astype(np.uint8)*255).save(mask_folder/(path.stem+'-protected.png'))
            # Reopen the delivered PNG, rather than just checking an in-memory array.
            with Image.open(destination/path.name) as saved:
                check = np.array(saved)
                if saved.mode != 'RGBA' or check.shape != rgba.shape or not np.array_equal(check, fixed):
                    raise ValueError(f'PNG round-trip failed: {path.name}')
                if not (check[:, :, 3] == 0).any():
                    raise ValueError(f'No transparent background: {path.name}')
            summary.append({'frame': path.name, **stats})
            if i % 24 == 0 or i == len(frames):
                print(f'{folder.name}: {i}/{len(frames)}', flush=True)
        report.append({'folder': folder.name, 'frames': len(frames), 'details': summary})
    report_path = batch/('sample-report.json' if args.samples else 'repair-report.json')
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print('Completed '+str(report_path), flush=True)


if __name__ == '__main__':
    main()
