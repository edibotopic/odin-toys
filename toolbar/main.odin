package main

import rl "vendor:raylib"

WIN_WIDTH: i32 = 300
WIN_HEIGHT: i32 = 300
CUT_SIZE: f32 = 30

main :: proc() {

	rl.SetTargetFPS(500)

	// toolbar is a long narrow rectangle
	toolbar := Rect {
		x      = 0,
		y      = 0,
		width  = 300,
		height = 30,
	}

	// cut the toolbar thrice on the left and once on the right
	cutLeft1 := cut_rect_left(&toolbar, CUT_SIZE, 0)
	cutLeft2 := cut_rect_left(&toolbar, CUT_SIZE, 0)
	cutLeft3 := cut_rect_left(&toolbar, CUT_SIZE, 0)
	cutRight1 := cut_rect_right(&toolbar, CUT_SIZE, 0)

	rl.InitWindow(WIN_WIDTH, WIN_HEIGHT, "rect cut example")
	defer rl.CloseWindow()

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLUE)

		// draw toolbar with fill
		rl.DrawRectangleV({0, 0}, {f32(WIN_WIDTH), CUT_SIZE}, rl.PINK)

		// draw cut sections with fill
		rl.DrawRectangleV({cutLeft1.x, cutLeft1.y}, {cutLeft1.width, cutLeft1.height}, rl.PINK)
		rl.DrawRectangleV({cutLeft2.x, cutLeft2.y}, {cutLeft2.width, cutLeft2.height}, rl.PINK)
		rl.DrawRectangleV({cutLeft3.x, cutLeft3.y}, {cutLeft3.width, cutLeft3.height}, rl.PINK)
		rl.DrawRectangleV({cutRight1.x, cutRight1.y}, {cutRight1.width, cutRight1.height}, rl.PINK)

		// draw separators between sections
		rl.DrawLine(
			i32(cutLeft1.x + cutLeft1.width),
			0,
			i32(cutLeft1.x + cutLeft1.width),
			i32(CUT_SIZE),
			rl.BLACK,
		)
		rl.DrawLine(
			i32(cutLeft2.x + cutLeft2.width),
			0,
			i32(cutLeft2.x + cutLeft2.width),
			i32(CUT_SIZE),
			rl.BLACK,
		)
		rl.DrawLine(
			i32(cutLeft3.x + cutLeft3.width),
			0,
			i32(cutLeft3.x + cutLeft3.width),
			i32(CUT_SIZE),
			rl.BLACK,
		)
		rl.DrawLine(i32(cutRight1.x), 0, i32(cutRight1.x), i32(CUT_SIZE), rl.BLACK)

		// draw toolbar outline
		rl.DrawRectangleLinesEx(rl.Rectangle{0, 0, 300, 30}, 1, rl.BLACK)
		rl.EndDrawing()
	}
}
