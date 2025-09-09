package bunnymark

import rl "vendor:raylib"

// -----------------------------------------------------------------------------
// BunnyMark (Odin dev-2025-09-nightly:42c2cb8 + raylib 5.5)
//
// Controls:
//   - Left mouse click  : add N bunnies (hold Shift → x10)
//   - Right mouse click : remove N bunnies (hold Shift → x10)
//
// Layout of this file follows a common, readable order:
//   1) constants
//   2) types
//   3) globals
//   4) utils
//   5) systems (input/update/render/add/remove)
//   6) entry point
// -----------------------------------------------------------------------------

// 1) CONSTANTS ----------------------------------------------------------------

// Upper limit for the number of live bunnies held in arrays
MAX_ARRAY :: 500_000

// 2) TYPES --------------------------------------------------------------------

// Per-bunny state (AoS). If you need more CPU cache efficiency later,
// consider switching to SoA (separate arrays for x/y/speed_x/speed_y/tint).
Bunny :: struct {
	x:       f32, // position X (pixels)
	y:       f32, // position Y (pixels)
	speed_x: f32, // velocity X (pixels per frame)
	speed_y: f32, // velocity Y (pixels per frame)
	tint:    rl.Color, // color multiplied with the texture at draw time
}

// 3) GLOBALS ------------------------------------------------------------------

// Index of the last valid bunny in the array (-1 means “empty”)
index_array: i32 = -1

// Fixed-capacity storage for all bunnies. Only [0 .. index_array] are valid.
bunnies: [MAX_ARRAY]Bunny

// Shared sprite texture (one texture = optimal batching in raylib)
bunny_tex: rl.Texture2D

// World settings and bounds. NOTE: current logic is frame-based (px/frame).
gravity: f32 = 0.5 // added to speed_y each frame (px/frame²)
max_x: f32 = 0.0 // right bound (sprite’s left edge clamped to this)
max_y: f32 = 0.0 // bottom bound (sprite’s top edge clamped to this)
min_x: f32 = 0.0 // left bound
min_y: f32 = 0.0 // top bound

// 4) UTILS --------------------------------------------------------------------

// Pseudo-random scalar in [0,1). Uses raylib’s GetRandomValue for simplicity.
random01 :: proc() -> f32 {
	return f32(rl.GetRandomValue(0, 1_000_000)) / 1_000_000.0
}

// 5) SYSTEMS ------------------------------------------------------------------

// Input: LMB adds, RMB removes. Holding Shift multiplies the amount by 10.
handle_input_clicks :: proc() {
	base: i32 = 1000
	mult: i32 = 1
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) {
		mult = 10
	}

	if rl.IsMouseButtonPressed(.LEFT) {
		add_bunnies(base * mult)
	}
	if rl.IsMouseButtonPressed(.RIGHT) {
		remove_bunnies(base * mult)
	}
}

// Create up to `total` new bunnies (respecting MAX_ARRAY).
// New bunnies spawn at (0,0) with random velocity and a bright HSV tint.
add_bunnies :: proc(total: i32) {
	if index_array == (MAX_ARRAY - 1) do return

	for i: i32 = 0; i < total; i += 1 {
		if (index_array + 1) < MAX_ARRAY {
			// Vivid tint via HSV (keeps saturation/value high)
			h := f32(rl.GetRandomValue(0, 359))
			s := 0.65 + random01() * 0.35
			v: f32 = 0.90
			tint := rl.ColorFromHSV(h, s, v)

			// NOTE: these velocities are in px/frame (frame-based simulation).
			// To make it frame-rate independent, convert to px/s and multiply by dt in update().
			b := Bunny {
				x       = 0.0,
				y       = 0.0,
				speed_x = random01() * 8.0, // 0..8 px/frame
				speed_y = random01() * 5.0 - 2.5, // -2.5..+2.5 px/frame
				tint    = tint,
			}
			index_array += 1
			bunnies[index_array] = b
		} else do break
	}
}

// Remove up to `total` bunnies in O(1) by moving the “top” index down.
// We don't compact the array—render/update only iterate up to index_array.
remove_bunnies :: proc(total: i32) {
	if total <= 0 do return
	have := index_array + 1
	if have <= 0 do return
	n := total
	if n > have {n = have}
	index_array -= n
}

// Per-frame simulation (frame-based integration).
// Tip: for frame-rate independent motion, use update_bunnies(dt: f32)
// and keep speed in px/s, gravity in px/s².
update_bunnies :: proc() {
	for i: i32 = 0; i <= index_array; i += 1 {
		b := &bunnies[i]

		// Integrate position/velocity (per frame)
		b.x += b.speed_x
		b.y += b.speed_y
		b.speed_y += gravity

		// Horizontal walls: clamp and reflect X velocity
		if b.x > max_x {
			b.speed_x *= -1.0
			b.x = max_x
		} else if b.x < min_x {
			b.speed_x *= -1.0
			b.x = min_x
		}

		// Vertical bounds: floor bounce / ceiling stop
		if b.y > max_y {
			b.speed_y *= -0.8 // inelastic bounce on the floor
			b.y = max_y

			// Occasionally add an extra upward impulse for variety
			if random01() > 0.5 {
				b.speed_y -= 3.0 + random01() * 4.0
			}
		} else if b.y < min_y {
			b.speed_y = 0.0 // stop when touching the ceiling
			b.y = min_y
		}
	}
}

// Draw all bunnies and a text HUD.
// Using the same texture for every sprite keeps raylib’s internal batch intact.
render_bunnies :: proc() {
	for i: i32 = 0; i <= index_array; i += 1 {
		rl.DrawTextureV(
			bunny_tex,
			rl.Vector2{bunnies[i].x, bunnies[i].y}, // sub-pixel positions
			bunnies[i].tint, // per-sprite color
		)
	}

	// HUD: TextFormat returns a temporary cstring that DrawText can consume
	rl.DrawText(
		rl.TextFormat(
			"bunnies: %i  fps: %i  delta: %0.4f",
			index_array + 1,
			rl.GetFPS(),
			rl.GetFrameTime(),
		),
		10,
		10,
		20,
		rl.WHITE,
	)
}

// 6) ENTRY POINT --------------------------------------------------------------

main :: proc() {
	// Window size (in pixels)
	screen_width: i32 = 1280
	screen_height: i32 = 720

	// Enable VSYNC (swap throttles the frame rate). TargetFPS(0) avoids busy-wait.
	rl.SetConfigFlags(rl.ConfigFlags{.VSYNC_HINT})
	rl.InitWindow(screen_width, screen_height, "BunnyMark")
	rl.SetTargetFPS(0)

	// Load a single shared texture; drawing the same texture maximizes batching
	bunny_tex = rl.LoadTexture("assets/wabbit_alpha.png")

	// Smoother look for sub-pixel motion. For max throughput use POINT.
	rl.SetTextureFilter(bunny_tex, rl.TextureFilter.BILINEAR)

	// Compute movement bounds (so the sprite stays fully inside the window)
	max_x = f32(screen_width - bunny_tex.width)
	max_y = f32(screen_height - bunny_tex.height)

	// Background color (r,g,b,a)
	bg := rl.Color{42, 51, 71, 255}

	// Main loop
	for !rl.WindowShouldClose() {
		handle_input_clicks() // add/remove bunnies on clicks (Shift ×10)
		update_bunnies() // advance simulation one frame

		rl.BeginDrawing()
		rl.ClearBackground(bg)
		render_bunnies()
		rl.EndDrawing()
	}

	// Cleanup
	rl.UnloadTexture(bunny_tex)
	bunnies = {} // zeroing the array (not strictly required here)
	rl.CloseWindow()
}
