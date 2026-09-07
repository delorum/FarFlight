# Pilot sprite prompt

Use case: stylized-concept
Asset type: 2D side-view game character sprite sheet for a Godot game
Primary request: create a clean horizontal sprite sheet of a small pilot character walking to the right
Subject: one adult pilot/courier wearing a simple dark teal vintage aviation uniform, matching cap, light shirt, practical boots; readable human silhouette at small size
Style/medium: flat schematic 2D illustration, restrained retro technical-diagram style, crisp dark outlines, minimal shading, visually compatible with a beige topographic map interface
Composition/framing: exactly 6 equally sized non-overlapping square animation cells in one horizontal row; full body side profile in every cell; consistent scale, baseline, proportions and camera; sequential natural walk cycle facing right
Color palette: dark teal, muted blue-gray, warm off-white, small ochre accent
Constraints: genuinely transparent background and preserved alpha; generous transparent padding around every frame; no ground, no cast shadow, no scenery, no aircraft, no props, no text, no labels, no borders, no grid lines, no watermark; character must not overlap adjacent cells; suitable for downscaling to about 48 pixels tall
Avoid: photorealism, 3D rendering, painterly texture, changing costume or anatomy between frames, front-facing poses, cropped body

Godot usage: import without filtering for a pixel-crisp result, slice the single row into six equal frames, play at 8–10 FPS, and flip horizontally for movement to the left.
