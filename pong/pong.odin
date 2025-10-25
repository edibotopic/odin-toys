package main

import m "core:math/linalg/hlsl"
import rnd "core:math/rand"
import rl "vendor:raylib"

Window :: struct {
	name:   cstring,
	width:  i32,
	height: i32,
	fps:    i32,
}

Paddle :: struct {
	pos:       m.float2,
	vel:       m.float2, // Velocity for momentum
	spd:       f32,
	scr:       i32, // Points in current game
	games_won: i32, // Games won in match
	dim:       m.float2,
	col:       rl.Color,
	hit:       bool,
}

p1, p2: Paddle

Ball :: struct {
	pos: m.float2,
	vel: m.float2,
	r:   f32,
	col: rl.Color,
}

ball: Ball

Theme :: struct {
	bg_main:   rl.Color,
	txt_dark:  rl.Color,
	txt_light: rl.Color,
	p1:        rl.Color,
	p2:        rl.Color,
	ball:      rl.Color,
}

theme: Theme

State :: enum {
	LOGO,
	TITLE,
	MODE_SELECT,
	GAME,
	END,
}

GameMode :: enum {
	PONG,
	AIR_HOCKEY,
	SQUASH,
	TENNIS,
}

ModeConfig :: struct {
	name:                cstring,
	description:         cstring,

	// Physics
	ball_speed_mult:     f32,
	friction:            f32, // Multiplier applied each frame (1.0 = no friction)
	wall_dampening:      f32, // Energy lost on wall bounce
	paddle_dampening:    f32, // Energy lost on paddle hit
	spin_dampening:      f32,
	spin_acceleration:   f32,
	ball_scale_at_net:   bool, // Scale ball radius at net to simulate height
	net_speed_modifier:  f32, // Speed multiplier at net (tennis: 0.8 = slower at peak)
	ball_size_mult:      f32, // Ball radius multiplier (squash: smaller)

	// Gameplay
	win_score:           i32,
	single_player:       bool, // Player vs wall (squash)
	has_net:             bool, // Tennis has net obstacle
	net_height:          f32,

	// Visual theme
	bg_color:            rl.Color,
	court_primary:       rl.Color,
	court_secondary:     rl.Color,
	paddle_color:        rl.Color,
	ball_color:          rl.Color,
	text_color:          rl.Color,
	accent_color:        rl.Color,

	// UI customization
	show_rally_counter:  bool,
	rally_threshold:     i32, // Show excitement at this rally count
	countdown_enabled:   bool,
	paddle_rounded:      bool, // Circular paddles for air hockey

	// Paddle movement
	allow_x_movement:    bool, // Allow forward/backward movement (squash)
	paddle_momentum:     f32, // Momentum/inertia (1.0 = none, <1.0 = slide effect)
	paddle_acceleration: f32, // How quickly paddle reaches full speed

	// Goals (air hockey)
	has_goals:           bool, // Use goal zones instead of entire edge
	goal_size:           f32, // Height of goal as fraction of screen (0.4 = 40%)
}

current_mode: GameMode
mode_config: ModeConfig

main :: proc() {

	// INIT
	window := Window{"Pong", WIN_DIM.x, WIN_DIM.y, 60}

	// Initialize default mode
	current_mode = .PONG
	mode_config = getModeConfig(current_mode)
	selected_mode: GameMode = .PONG

	{
		using window
		rl.InitWindow(width, height, name)
	}


	rl.SetTargetFPS(window.fps)

	currentScreen := State.MODE_SELECT // Skip directly to mode selection
	framesCounter := 0
	scoreCounter := 0
	countdownTimer: i32 = 0
	rallyCount: i32 = 0
	isServing := false
	scoreFlashTimer: i32 = 0
	powerHitCooldown: i32 = 0 // Cooldown for P1 power hit in air hockey
	cpuPowerHitCooldown: i32 = 0 // Cooldown for CPU power hit in air hockey
	powerHitFlash: i32 = 0 // Flash effect for P1 power hit
	cpuPowerHitFlash: i32 = 0 // Flash effect for CPU power hit

	// Colors - will be updated per mode
	theme.bg_main = mode_config.bg_color
	theme.txt_dark = mode_config.text_color
	theme.txt_light = mode_config.court_secondary
	// Players are red (P1) and blue (P2)
	theme.p1 = rl.Color{255, 50, 50, 255} // Red
	theme.p2 = rl.Color{50, 100, 255, 255} // Blue
	theme.ball = mode_config.ball_color

	// Players
	p1.pos = m.float2{f32(P1_START_POS), f32(WIN_DIM.y / 2)}
	p2.pos = m.float2{f32(P2_START_POS), f32(WIN_DIM.y / 2)}
	p1.vel = m.float2{0, 0}
	p2.vel = m.float2{0, 0}
	p1.dim = m.float2{PLAYERS_WIDTH, PLAYERS_HEIGHT}
	p2.dim = m.float2{PLAYERS_WIDTH, PLAYERS_HEIGHT}
	p1.spd, p2.spd = P1_SPEED, CPU_SPEED
	p1.scr, p2.scr = MIN_SCORE, MIN_SCORE
	p1.games_won, p2.games_won = 0, 0

	// Audio
	rl.InitAudioDevice()
	strike_fx1 := rl.LoadSound("./assets/hit5.ogg") // paddle
	strike_fx2 := rl.LoadSound("./assets/hit2.ogg") // wall
	strike_fx3 := rl.LoadSound("./assets/hit4.ogg") // spin
	score_fx1 := rl.LoadSound("./assets/score3.ogg") // P1
	score_fx2 := rl.LoadSound("./assets/score4.ogg") // CPU
	back_fx1 := rl.LoadMusicStream("./assets/tuneSynth.ogg") // Game
	back_fx2 := rl.LoadMusicStream("./assets/tuneFullLargeWithGap.ogg") // Title
	rl.SetSoundVolume(strike_fx1, 0.4)

	// Ball
	ball.r = BALL_RADIUS
	ball.pos = {f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
	ball.vel = m.float2{rnd.float32_normal(X_MEAN, X_SDEV), rnd.float32_normal(Y_MEAN, Y_SDEV)}
	ball.col = theme.ball
	ball_prev_pos := ball.pos // Track previous position for continuous collision detection

	// Pause
	Paused: bool = false
	showQuitDialog: bool = false

	// UPDATE
	for !rl.WindowShouldClose() {

		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {Paused = !Paused}

		switch currentScreen {
		case .LOGO:
			{
				framesCounter += 1

				if framesCounter > 120 {
					currentScreen = State.MODE_SELECT
				}
			}; break
		case .TITLE:
			{
				rl.PlayMusicStream(back_fx2)
				rl.UpdateMusicStream(back_fx2)

				if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
					currentScreen = State.MODE_SELECT
				}
			}; break
		case .MODE_SELECT:
			{
				rl.UpdateMusicStream(back_fx2)
				rl.PlayMusicStream(back_fx2)

				// Navigate modes with arrow keys
				if rl.IsKeyPressed(rl.KeyboardKey.LEFT) {
					selected_mode = GameMode((int(selected_mode) - 1 + 4) % 4)
				} else if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) {
					selected_mode = GameMode((int(selected_mode) + 1) % 4)
				}

				// Select mode with ENTER
				if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
					current_mode = selected_mode
					mode_config = getModeConfig(current_mode)

					// Update theme colors for selected mode
					theme.bg_main = mode_config.bg_color
					theme.txt_dark = mode_config.text_color
					theme.txt_light = mode_config.court_secondary
					// Players are red (P1) and blue (P2)
					theme.p1 = rl.Color{255, 50, 50, 255} // Red
					theme.p2 = rl.Color{50, 100, 255, 255} // Blue
					theme.ball = mode_config.ball_color
					p1.col = theme.p1
					p2.col = theme.p2
					ball.col = mode_config.ball_color

					// Reset positions for new match
					p1.pos = m.float2{f32(P1_START_POS), f32(WIN_DIM.y / 2)}
					p2.pos = m.float2{f32(P2_START_POS), f32(WIN_DIM.y / 2)}
					p1.vel = m.float2{0, 0}
					p2.vel = m.float2{0, 0}
					p1.scr = MIN_SCORE
					p2.scr = MIN_SCORE
					p1.games_won = 0
					p2.games_won = 0

					currentScreen = State.GAME
					isServing = true
					countdownTimer = 180
					rallyCount = 0
					powerHitCooldown = 0
					powerHitFlash = 0
					cpuPowerHitCooldown = 0
					cpuPowerHitFlash = 0
				}

				// No back button - ESC to quit
			}; break
		case .GAME:
			{
				rl.StopMusicStream(back_fx2)
				rl.UpdateMusicStream(back_fx1)
				rl.PlayMusicStream(back_fx1)

				if !Paused && !showQuitDialog {
					rl.SetMusicVolume(back_fx1, 0.8)
				} else {
					rl.SetMusicVolume(back_fx1, 0.2)
				}

				// Handle quit dialog
				if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
					if showQuitDialog {
						// Cancel quit dialog
						showQuitDialog = false
					} else {
						// Show quit dialog
						showQuitDialog = true
					}
				}

				if showQuitDialog && rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
					// Confirm quit to menu
					showQuitDialog = false
					currentScreen = State.MODE_SELECT
					// Reset scores and games
					p1.scr = MIN_SCORE
					p2.scr = MIN_SCORE
					p1.games_won = 0
					p2.games_won = 0
					// Reset ball state so it doesn't carry over to next mode
					ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
					ball.vel = m.float2 {
						rnd.float32_normal(X_MEAN, X_SDEV),
						rnd.float32_normal(Y_MEAN, Y_SDEV),
					}
					powerHitCooldown = 0
					powerHitFlash = 0
					cpuPowerHitCooldown = 0
					cpuPowerHitFlash = 0
				}

				// Check for game win (reaching win_score)
				if p1.scr == mode_config.win_score {
					p1.games_won += 1
					if p1.games_won >= 2 {
						// Match won!
						currentScreen = State.END
						showQuitDialog = false
					} else {
						// Game won, prepare for next game
						p1.scr = MIN_SCORE
						p2.scr = MIN_SCORE
						swapSides()
						ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
						ball.vel = m.float2 {
							rnd.float32_normal(X_MEAN, X_SDEV),
							rnd.float32_normal(Y_MEAN, Y_SDEV),
						}
						isServing = true
						countdownTimer = 180
						rallyCount = 0
						powerHitCooldown = 0
						powerHitFlash = 0
						cpuPowerHitCooldown = 0
						cpuPowerHitFlash = 0
					}
				} else if p2.scr == mode_config.win_score {
					p2.games_won += 1
					if p2.games_won >= 2 {
						// Match won!
						currentScreen = State.END
						showQuitDialog = false
					} else {
						// Game won, prepare for next game
						p1.scr = MIN_SCORE
						p2.scr = MIN_SCORE
						swapSides()
						ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
						ball.vel = m.float2 {
							rnd.float32_normal(X_MEAN, X_SDEV),
							rnd.float32_normal(Y_MEAN, Y_SDEV),
						}
						isServing = true
						countdownTimer = 180
						rallyCount = 0
						powerHitCooldown = 0
						powerHitFlash = 0
						cpuPowerHitCooldown = 0
						cpuPowerHitFlash = 0
					}
				} else if rl.IsKeyDown(rl.KeyboardKey.X) {
					currentScreen = State.END
					showQuitDialog = false
				} else if rl.IsKeyDown(rl.KeyboardKey.B) {
					debugShow()
				}
			}; break
		case .END:
			{
				rl.StopMusicStream(back_fx1)

				if rl.IsKeyDown(rl.KeyboardKey.ENTER) {
					currentScreen = State.GAME
					// Reset for new match
					p1.pos = m.float2{f32(P1_START_POS), f32(WIN_DIM.y / 2)}
					p2.pos = m.float2{f32(P2_START_POS), f32(WIN_DIM.y / 2)}
					p1.vel = m.float2{0, 0}
					p2.vel = m.float2{0, 0}
					p1.scr = MIN_SCORE
					p2.scr = MIN_SCORE
					p1.games_won = 0
					p2.games_won = 0
					ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
					ball.vel = m.float2 {
						rnd.float32_normal(X_MEAN, X_SDEV),
						rnd.float32_normal(Y_MEAN, Y_SDEV),
					}
					isServing = true
					countdownTimer = 180
					rallyCount = 0
					powerHitCooldown = 0
					powerHitFlash = 0
					cpuPowerHitCooldown = 0
					cpuPowerHitFlash = 0
				}
			}; break
		}

		// DRAW
		rl.BeginDrawing()

		rl.ClearBackground(theme.bg_main)

		switch currentScreen {
		case .LOGO:
			{
				drawLogo()

			}; break
		case .TITLE:
			{
				drawTitle()

			}; break
		case .MODE_SELECT:
			{
				drawModeSelect(selected_mode)

			}; break
		case .GAME:
			{
				drawNet()

				drawGoals()

				drawScores(scoreFlashTimer)

				// Draw Paddles (mode-specific shape)
				P1: rl.Rectangle = {f32(p1.pos.x), f32(p1.pos.y), p1.dim.x, p1.dim.y}
				P2: rl.Rectangle = {f32(p2.pos.x), f32(p2.pos.y), p2.dim.x, p2.dim.y}

				if mode_config.paddle_rounded {
					// Circular paddles (air hockey mallets)
					paddle_radius := p1.dim.x
					rl.DrawCircle(
						i32(p1.pos.x + paddle_radius),
						i32(p1.pos.y + p1.dim.y / 2),
						paddle_radius,
						p1.col,
					)
					if !mode_config.single_player {
						rl.DrawCircle(
							i32(p2.pos.x + paddle_radius),
							i32(p2.pos.y + p2.dim.y / 2),
							paddle_radius,
							p2.col,
						)
					}
				} else {
					// Rectangle paddles
					rl.DrawRectangleRounded(P1, 0.7, 0, p1.col)
					if !mode_config.single_player {
						rl.DrawRectangleRounded(P2, 0.7, 0, p2.col)
					}
				}

				// Squash: draw walls on both sides
				if mode_config.single_player {
					// Back wall (left)
					rl.DrawRectangle(0, 0, 10, WIN_DIM.y, mode_config.court_secondary)
					// Front wall (right)
					wall_x := WIN_DIM.x - 10
					rl.DrawRectangle(wall_x, 0, 10, WIN_DIM.y, mode_config.court_primary)
				}

				drawBall()

				// Draw countdown if serving
				if isServing {
					drawCountdown(countdownTimer)
				}

				// Draw rally counter
				drawRallyCounter(rallyCount)

				// Draw power hit cooldown indicator (air hockey only)
				if mode_config.paddle_rounded {
					cooldown_text: cstring
					cooldown_color := theme.txt_light
					if powerHitCooldown > 0 {
						cooldown_text = rl.TextFormat("Power Hit: %i", powerHitCooldown / 60 + 1)
						cooldown_color = rl.Color{150, 150, 150, 255} // Gray when on cooldown
					} else {
						cooldown_text = "Power Hit: ENTER"
						cooldown_color = mode_config.accent_color // Highlight when ready
					}
					text_size: i32 = 16
					text_width := rl.MeasureText(cooldown_text, text_size)
					rl.DrawText(cooldown_text, 10, WIN_DIM.y - 25, text_size, cooldown_color)

					// Flash effect when P1 power hit is used
					if powerHitFlash > 0 {
						flash_alpha := f32(powerHitFlash) / 15.0
						rl.DrawCircle(
							i32(p1.pos.x + p1.dim.x),
							i32(p1.pos.y + p1.dim.y / 2),
							p1.dim.x * 2.0,
							rl.ColorAlpha(mode_config.accent_color, flash_alpha * 0.5),
						)
					}

					// Flash effect when CPU power hit is used
					if cpuPowerHitFlash > 0 {
						flash_alpha := f32(cpuPowerHitFlash) / 15.0
						rl.DrawCircle(
							i32(p2.pos.x + p2.dim.x),
							i32(p2.pos.y + p2.dim.y / 2),
							p2.dim.x * 2.0,
							rl.ColorAlpha(mode_config.accent_color, flash_alpha * 0.5),
						)
					}
				}

				if !Paused && !showQuitDialog {

					// Countdown logic
					if isServing {
						countdownTimer -= 1
						if countdownTimer <= 0 {
							isServing = false
						}
					}

					// Decrement score flash
					if scoreFlashTimer > 0 {
						scoreFlashTimer -= 1
					}

					// Decrement power hit cooldown and flash
					if powerHitCooldown > 0 {
						powerHitCooldown -= 1
					}
					if powerHitFlash > 0 {
						powerHitFlash -= 1
					}
					if cpuPowerHitCooldown > 0 {
						cpuPowerHitCooldown -= 1
					}
					if cpuPowerHitFlash > 0 {
						cpuPowerHitFlash -= 1
					}

					// Always allow player/CPU movement (even during countdown)
					playerControls()

					// CPU only in multiplayer modes
					if !mode_config.single_player {
						cpuAI()
					}

					setBoundaries()

					// Only move ball when not in countdown
					if !isServing {
						// Store previous position before moving
						ball_prev_pos = ball.pos
						moveBall()
					}

					p1.hit = false
					p2.hit = false

					// Air hockey power hit mechanic (Player)
					// BUG: powerhit direction wrong after side switch
					if mode_config.paddle_rounded && !isServing {
						if rl.IsKeyPressed(rl.KeyboardKey.ENTER) && powerHitCooldown == 0 {
							// Check if ball is close enough to P1 for power hit
							paddle_radius := p1.dim.x
							p1_center := m.float2 {
								p1.pos.x + paddle_radius,
								p1.pos.y + p1.dim.y / 2,
							}
							dist_to_ball := m.distance(ball.pos, p1_center)
							hit_range: f32 = 60.0 // Can hit from slightly farther away

							if dist_to_ball < hit_range {
								// Power hit! Launch ball toward opponent at high speed
								// Direction: mostly horizontal (toward opponent) with slight Y angle
								y_offset := (ball.pos.y - p1_center.y) / paddle_radius // Normalized -1 to 1
								p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
								x_dir: f32
								if p1_on_left {
									x_dir = 0.95
								} else {
									x_dir = -0.95
								}
								direction := m.float2{x_dir, y_offset * 0.15} // Launch toward opponent
								direction = m.normalize(direction)
								ball.vel = direction * 6.0 // High speed launch
								powerHitCooldown = 120 // 2 second cooldown
								powerHitFlash = 15 // Flash effect
								rl.PlaySound(strike_fx3) // Play power hit sound
								p1.hit = true
							}
						}

						// CPU power hit AI
						if !mode_config.single_player && cpuPowerHitCooldown == 0 {
							paddle_radius := p2.dim.x
							p2_center := m.float2 {
								p2.pos.x + paddle_radius,
								p2.pos.y + p2.dim.y / 2,
							}
							dist_to_ball := m.distance(ball.pos, p2_center)
							hit_range: f32 = 60.0

							// CPU uses power hit when ball is slow and close
							ball_speed := m.length(ball.vel)
							if dist_to_ball < hit_range && ball_speed < 2.0 {
								// CPU power hit!
								y_offset := (ball.pos.y - p2_center.y) / paddle_radius
								direction := m.float2{-0.95, y_offset * 0.15} // Toward left (opponent)
								direction = m.normalize(direction)
								ball.vel = direction * 6.0
								cpuPowerHitCooldown = 120
								cpuPowerHitFlash = 15
								rl.PlaySound(strike_fx3)
								p2.hit = true
							}
						}
					}

					// Collision logic
					collision_radius := getBallCollisionRadius()

					if ball.pos.y - collision_radius < 0 {
						ball.pos.y = 0 + collision_radius
						ball.vel.y = -ball.vel.y * mode_config.wall_dampening
						rl.PlaySound(strike_fx2)
					} else if ball.pos.y + collision_radius > f32(WIN_DIM.y) {
						ball.pos.y = (f32(WIN_DIM.y) - collision_radius)
						ball.vel.y = -ball.vel.y * mode_config.wall_dampening
						rl.PlaySound(strike_fx2)
					} else if mode_config.paddle_rounded {
						// Air hockey: circular mallet collision (circle to circle)
						paddle_radius := p1.dim.x
						p1_center := m.float2{p1.pos.x + paddle_radius, p1.pos.y + p1.dim.y / 2}
						p2_center := m.float2{p2.pos.x + paddle_radius, p2.pos.y + p2.dim.y / 2}

						// Check P1 collision
						dist_to_p1 := m.distance(ball.pos, p1_center)
						if dist_to_p1 < collision_radius + paddle_radius {
							// Push ball away from paddle to prevent multiple collisions
							collision_normal := m.normalize(ball.pos - p1_center)
							ball.pos =
								p1_center +
								collision_normal * (collision_radius + paddle_radius + 1.0)

							handlePaddleCollision(&p1, strike_fx1, strike_fx3)
							rallyCount += 1
						}

						// Check P2 collision
						dist_to_p2 := m.distance(ball.pos, p2_center)
						if dist_to_p2 < collision_radius + paddle_radius {
							// Push ball away from paddle to prevent multiple collisions
							collision_normal := m.normalize(ball.pos - p2_center)
							ball.pos =
								p2_center +
								collision_normal * (collision_radius + paddle_radius + 1.0)

							handlePaddleCollision(&p2, strike_fx1, strike_fx3)
							rallyCount += 1
						}
					} else if rl.CheckCollisionCircleRec(
						{ball.pos.x, ball.pos.y},
						collision_radius,
						P1,
					) {
						// Determine which side P1 is on for proper collision detection
						p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)

						// Squash mode: paddle can hit from both sides
						if mode_config.single_player {
							// Check which side of paddle was hit
							paddle_center_x := p1.pos.x + p1.dim.x / 2
							if ball.pos.x > paddle_center_x {
								// Hit front of paddle - send ball right
								ball.vel.x = m.abs(ball.vel.x) * mode_config.paddle_dampening
							} else {
								// Hit back of paddle - send ball left
								ball.vel.x = -m.abs(ball.vel.x) * mode_config.paddle_dampening
							}
							// Apply spin if W/S pressed
							if rl.IsKeyDown(rl.KeyboardKey.W) || rl.IsKeyDown(rl.KeyboardKey.S) {
								ball.vel.y = -ball.vel.y * mode_config.spin_acceleration
								rl.PlaySound(strike_fx3)
							} else {
								rl.PlaySound(strike_fx1)
							}
							p1.hit = true
						} else {
							// Normal pong: only hit from correct side based on position
							ball_coming_toward_p1 :=
								(p1_on_left && ball.vel.x < 0) || (!p1_on_left && ball.vel.x > 0)
							if ball_coming_toward_p1 {
								handlePaddleCollision(&p1, strike_fx1, strike_fx3)
							}
						}
						rallyCount += 1
					} else if !mode_config.single_player &&
					   rl.CheckCollisionCircleRec({ball.pos.x, ball.pos.y}, collision_radius, P2) {
						// Determine which side P2 is on for proper collision detection
						p2_on_left := p2.pos.x < f32(WIN_DIM.x / 2)
						ball_coming_toward_p2 :=
							(p2_on_left && ball.vel.x < 0) || (!p2_on_left && ball.vel.x > 0)

						if ball_coming_toward_p2 {
							handlePaddleCollision(&p2, strike_fx1, strike_fx3)
							rallyCount += 1
						}
					}

					// Squash: bounce off both left and right walls
					if mode_config.single_player {
						if ball.pos.x + collision_radius > f32(WIN_DIM.x - 10) && ball.vel.x > 0 {
							// Front wall (right side)
							ball.pos.x = f32(WIN_DIM.x - 10) - collision_radius
							ball.vel.x = -ball.vel.x * mode_config.wall_dampening
							rl.PlaySound(strike_fx2)
							rallyCount += 1
						} else if ball.pos.x - collision_radius < 10 && ball.vel.x < 0 {
							// Back wall (left side)
							ball.pos.x = 10 + collision_radius
							ball.vel.x = -ball.vel.x * mode_config.wall_dampening
							rl.PlaySound(strike_fx2)
							rallyCount += 1
						}
					}

					if p1.hit == true {
						p1.col = ball.col
					} else if p2.hit == true {
						p2.col = ball.col
					} else {
						p1.col, p2.col = theme.p1, theme.p2
					}

					// Score logic
					// BUG: broken after side switch
					if mode_config.single_player {
						// Squash: lose point when ball stops moving
						ball_speed := m.length(ball.vel)
						if ball_speed < 0.5 { 	// Ball essentially stopped
							scoreCounter += 1

							if scoreCounter > 60 {
								p2.scr += 1 // "Wall" scores (player error)
								rl.PlaySound(score_fx2)

								// Reset positions
								p1.pos.y = f32(WIN_DIM.y / 2)
								p2.pos.y = f32(WIN_DIM.y / 2)
								p1.vel = m.float2{0, 0}
								p2.vel = m.float2{0, 0}

								ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
								ball.vel = m.float2 {
									rnd.float32_normal(X_MEAN, X_SDEV),
									rnd.float32_normal(Y_MEAN, Y_SDEV),
								}
								scoreCounter = 0
								rallyCount = 0
								isServing = true
								countdownTimer = 180
								scoreFlashTimer = 30
							}
						} else {
							scoreCounter = 0 // Reset if ball is still moving
						}
					} else {
						// Multiplayer modes scoring
						if mode_config.has_goals {
							// Air hockey: goals are openings, walls around them bounce
							goal_height := f32(WIN_DIM.y) * mode_config.goal_size
							goal_y_start := (f32(WIN_DIM.y) - goal_height) / 2
							goal_y_end := goal_y_start + goal_height
							goal_line_left: f32 = 0
							goal_line_right: f32 = f32(WIN_DIM.x)
							goal_depth: f32 = 15

							// Left side - check if ball crossed goal line (continuous collision)
							if ball_prev_pos.x >= goal_line_left && ball.pos.x < goal_line_left {
								// Ball crossed left goal line this frame
								in_goal_zone :=
									ball.pos.y >= goal_y_start && ball.pos.y <= goal_y_end

								if in_goal_zone {
									// Goal scored! Award point to player on RIGHT side
									p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
									if p1_on_left {
										// P1 is on left, so P2 (on right) scores
										p2.scr += 1
										rl.PlaySound(score_fx2)
									} else {
										// P1 is on right, so P1 scores
										p1.scr += 1
										rl.PlaySound(score_fx1)
									}

									// Reset positions
									p1.pos.y = f32(WIN_DIM.y / 2)
									p2.pos.y = f32(WIN_DIM.y / 2)
									p1.vel = m.float2{0, 0}
									p2.vel = m.float2{0, 0}

									ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
									ball.vel = m.float2 {
										rnd.float32_normal(X_MEAN, X_SDEV),
										rnd.float32_normal(Y_MEAN, Y_SDEV),
									}
									rallyCount = 0
									isServing = true
									countdownTimer = 180
									scoreFlashTimer = 30
								} else {
									// Ball hit wall outside goal - bounce
									ball.pos.x = goal_depth + collision_radius
									ball.vel.x = -ball.vel.x * mode_config.wall_dampening
									rl.PlaySound(strike_fx2)
								}
							} else if ball.pos.x - collision_radius < goal_depth &&
							   ball.vel.x < 0 {
								// Ball approaching left wall - check if it will hit wall
								in_goal_zone :=
									ball.pos.y >= goal_y_start && ball.pos.y <= goal_y_end
								if !in_goal_zone {
									// Ball hit wall outside goal - bounce
									ball.pos.x = goal_depth + collision_radius
									ball.vel.x = -ball.vel.x * mode_config.wall_dampening
									rl.PlaySound(strike_fx2)
								}
							}

							// Right side - check if ball crossed goal line (continuous collision)
							if ball_prev_pos.x <= goal_line_right && ball.pos.x > goal_line_right {
								// Ball crossed right goal line this frame
								in_goal_zone :=
									ball.pos.y >= goal_y_start && ball.pos.y <= goal_y_end

								if in_goal_zone {
									// Goal scored! Award point to player on LEFT side
									p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
									if p1_on_left {
										// P1 is on left, so P1 scores
										p1.scr += 1
										rl.PlaySound(score_fx1)
									} else {
										// P1 is on right, so P2 (on left) scores
										p2.scr += 1
										rl.PlaySound(score_fx2)
									}

									// Reset positions
									p1.pos.y = f32(WIN_DIM.y / 2)
									p2.pos.y = f32(WIN_DIM.y / 2)
									p1.vel = m.float2{0, 0}
									p2.vel = m.float2{0, 0}

									ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
									ball.vel = m.float2 {
										rnd.float32_normal(-X_MEAN, X_SDEV),
										rnd.float32_normal(Y_MEAN, Y_SDEV),
									}
									rallyCount = 0
									isServing = true
									countdownTimer = 180
									scoreFlashTimer = 30
								} else {
									// Ball hit wall outside goal - bounce
									ball.pos.x = f32(WIN_DIM.x) - goal_depth - collision_radius
									ball.vel.x = -ball.vel.x * mode_config.wall_dampening
									rl.PlaySound(strike_fx2)
								}
							} else if ball.pos.x + collision_radius >
								   f32(WIN_DIM.x) - goal_depth &&
							   ball.vel.x > 0 {
								// Ball approaching right wall - check if it will hit wall
								in_goal_zone :=
									ball.pos.y >= goal_y_start && ball.pos.y <= goal_y_end
								if !in_goal_zone {
									// Ball hit wall outside goal - bounce
									ball.pos.x = f32(WIN_DIM.x) - goal_depth - collision_radius
									ball.vel.x = -ball.vel.x * mode_config.wall_dampening
									rl.PlaySound(strike_fx2)
								}
							}
						} else {
							// Pong/Tennis: entire edge is goal
							if ball.pos.x < 0 {
								scoreCounter += 1

								if scoreCounter > 60 {
									p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
									if p1_on_left {
										p2.scr += 1
										rl.PlaySound(score_fx2)
									} else {
										p1.scr += 1
										rl.PlaySound(score_fx1)
									}

									// Reset positions
									p1.pos.y = f32(WIN_DIM.y / 2)
									p2.pos.y = f32(WIN_DIM.y / 2)
									p1.vel = m.float2{0, 0}
									p2.vel = m.float2{0, 0}

									ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
									ball.vel = m.float2 {
										rnd.float32_normal(X_MEAN, X_SDEV),
										rnd.float32_normal(Y_MEAN, Y_SDEV),
									}
									scoreCounter = 0
									rallyCount = 0
									isServing = true
									countdownTimer = 180
									scoreFlashTimer = 30
								}
							} else if ball.pos.x > f32(WIN_DIM.x) {
								scoreCounter += 1

								if scoreCounter > 60 {
									p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
									if p1_on_left {
										p1.scr += 1
										rl.PlaySound(score_fx1)
									} else {
										p2.scr += 1
										rl.PlaySound(score_fx2)
									}

									// Reset positions
									p1.pos.y = f32(WIN_DIM.y / 2)
									p2.pos.y = f32(WIN_DIM.y / 2)
									p1.vel = m.float2{0, 0}
									p2.vel = m.float2{0, 0}

									ball.pos = m.float2{f32(WIN_DIM.x / 2), f32(WIN_DIM.y / 2)}
									ball.vel = m.float2 {
										rnd.float32_normal(-X_MEAN, X_SDEV),
										rnd.float32_normal(Y_MEAN, Y_SDEV),
									}
									scoreCounter = 0
									rallyCount = 0
									isServing = true
									countdownTimer = 180
									scoreFlashTimer = 30
								}
							}
						}
					}

					trackWinner()
				}

				if Paused {
					rl.DrawText(
						"Paused",
						WIN_DIM.x / 2 - rl.MeasureText("Paused", 40) / 2,
						WIN_DIM.y / 2,
						40,
						theme.txt_dark,
					)
				}

				// Draw quit dialog
				if showQuitDialog {
					// Semi-transparent overlay
					rl.DrawRectangle(0, 0, WIN_DIM.x, WIN_DIM.y, rl.Color{0, 0, 0, 150})

					// Dialog box
					box_width: i32 = 400
					box_height: i32 = 150
					box_x := WIN_DIM.x / 2 - box_width / 2
					box_y := WIN_DIM.y / 2 - box_height / 2

					rl.DrawRectangle(box_x, box_y, box_width, box_height, theme.bg_main)
					rl.DrawRectangleLines(box_x, box_y, box_width, box_height, theme.txt_dark)

					// Title
					title_text: cstring = "Return to Menu?"
					title_size: i32 = 30
					title_width := rl.MeasureText(title_text, title_size)
					rl.DrawText(
						title_text,
						WIN_DIM.x / 2 - title_width / 2,
						box_y + 30,
						title_size,
						theme.txt_dark,
					)

					// Instructions
					inst1: cstring = "ENTER - Yes, quit to menu"
					inst2: cstring = "BACKSPACE - No, resume game"
					inst_size: i32 = 16
					inst1_width := rl.MeasureText(inst1, inst_size)
					inst2_width := rl.MeasureText(inst2, inst_size)

					rl.DrawText(
						inst1,
						WIN_DIM.x / 2 - inst1_width / 2,
						box_y + 80,
						inst_size,
						mode_config.accent_color,
					)
					rl.DrawText(
						inst2,
						WIN_DIM.x / 2 - inst2_width / 2,
						box_y + 105,
						inst_size,
						theme.txt_light,
					)
				}

			}; break
		case .END:
			{
				drawEndScreen()
			}; break
		}

		rl.EndDrawing()
	}

	rl.UnloadSound(score_fx1)
	rl.UnloadSound(score_fx2)
	rl.UnloadSound(strike_fx1)
	rl.UnloadSound(strike_fx2)
	rl.UnloadSound(strike_fx3)
	rl.UnloadMusicStream(back_fx1)
	rl.UnloadMusicStream(back_fx2)

	// CLOSE
	rl.CloseWindow()
}

// Constants and Globals
WIN_DIM :: m.int2{600, 400}

// Theme
CHAMPAGNE :: rl.Color{255, 221, 163, 255}
MUDDY :: rl.Color{115, 86, 63, 255}
SANDY :: rl.Color{127, 106, 79, 255}
BLUEISH :: rl.Color{121, 173, 160, 255}
ORANGE1 :: rl.Color{214, 86, 58, 255}
ORANGE2 :: rl.Color{229, 130, 64, 255}
ORANGE3 :: rl.Color{244, 165, 68, 255}

// Random
X_MEAN: f32 : 2.8
X_SDEV: f32 : 0.3
Y_MEAN: f32 : 0.5
Y_SDEV: f32 : 0.2

// Collisions
DAMP_WALL: f32 : 0.7
DAMP_SPIN: f32 : 0.8
ACCEL_SPIN: f32 : 1.5

// Physics
BALL_RADIUS: f32 : 10.0
BALL_SPEED_MULT: f32 : 1.1

// Players
P1_START_POS: i32 : 30
P2_START_POS: i32 : 555
PLAYERS_WIDTH: f32 : 15.0
PLAYERS_HEIGHT: f32 : 60.0
P1_SPEED: f32 = 2.5 // Faster for air hockey
CPU_SPEED: f32 = 1.5

// Scores
MIN_SCORE: i32 : 0
MAX_SCORE: i32 : 4
winner: string = "It's a draw!"

// Procedures

getModeConfig :: proc(mode: GameMode) -> ModeConfig {
	switch mode {
	case .PONG:
		return ModeConfig {
			name                = "CLASSIC PONG",
			description         = "Retro table tennis action",

			// Physics - classic pong feel
			ball_speed_mult     = BALL_SPEED_MULT,
			friction            = 1.0,
			wall_dampening      = DAMP_WALL,
			paddle_dampening    = BALL_SPEED_MULT,
			spin_dampening      = DAMP_SPIN,
			spin_acceleration   = ACCEL_SPIN,
			ball_scale_at_net   = false,
			net_speed_modifier  = 1.0,
			ball_size_mult      = 1.0,

			// Gameplay
			win_score           = 3, // Best of 3 games (first to 2 games wins match)
			single_player       = false,
			has_net             = false,
			net_height          = 0,

			// Visual - classic black and white
			bg_color            = rl.Color{0, 0, 0, 255}, // Black
			court_primary       = rl.Color{255, 255, 255, 255}, // White
			court_secondary     = rl.Color{128, 128, 128, 255}, // Gray
			paddle_color        = rl.Color{255, 255, 255, 255}, // White (will be overridden per player)
			ball_color          = rl.Color{255, 255, 255, 255}, // White
			text_color          = rl.Color{255, 255, 255, 255}, // White
			accent_color        = rl.Color{200, 200, 200, 255}, // Light gray

			// UI
			show_rally_counter  = true,
			rally_threshold     = 10,
			countdown_enabled   = true,
			paddle_rounded      = false,

			// Paddle movement
			allow_x_movement    = false,
			paddle_momentum     = 1.0, // No momentum
			paddle_acceleration = 1.0,

			// Goals
			has_goals           = false,
			goal_size           = 1.0,
		}

	case .AIR_HOCKEY:
		return ModeConfig {
			name                = "AIR HOCKEY",
			description         = "Fast frictionless puck action",

			// Physics - very fast with sliding puck
			ball_speed_mult     = 1.6, // Much faster
			friction            = 0.995, // Slight friction for puck sliding
			wall_dampening      = 0.95, // Bouncy walls
			paddle_dampening    = 1.05, // Minimal speed boost on hit
			spin_dampening      = 0.95,
			spin_acceleration   = 1.2,
			ball_scale_at_net   = false,
			net_speed_modifier  = 1.0,
			ball_size_mult      = 1.0,

			// Gameplay
			win_score           = 3, // Best of 3 games (first to 2 games wins match)
			single_player       = false,
			has_net             = false,
			net_height          = 0,

			// Visual - white ice rink
			bg_color            = rl.Color{240, 245, 250, 255}, // White ice
			court_primary       = rl.Color{180, 190, 200, 255}, // Light gray markings
			court_secondary     = rl.Color{100, 120, 140, 255}, // Blue-gray center line
			paddle_color        = rl.Color{255, 50, 50, 255}, // Red (will be overridden per player)
			ball_color          = rl.Color{20, 20, 20, 255}, // Black puck
			text_color          = rl.Color{40, 40, 40, 255}, // Dark gray text
			accent_color        = rl.Color{255, 200, 0, 255}, // Gold for goals

			// UI
			show_rally_counter  = true,
			rally_threshold     = 15,
			countdown_enabled   = true,
			paddle_rounded      = true, // Circular mallets

			// Paddle movement
			allow_x_movement    = true, // Can move in their half
			paddle_momentum     = 0.92, // More dramatic sliding effect
			paddle_acceleration = 0.25, // Gradual acceleration

			// Goals
			has_goals           = true,
			goal_size           = 0.4, // 40% of screen height
		}

	case .SQUASH:
		return ModeConfig {
			name                = "SQUASH",
			description         = "Solo wall training mode",

			// Physics - very fast, smaller ball
			ball_speed_mult     = 2.0, // Very fast
			friction            = 1.0,
			wall_dampening      = 0.85,
			paddle_dampening    = 1.2,
			spin_dampening      = 0.8,
			spin_acceleration   = 1.3,
			ball_scale_at_net   = false,
			net_speed_modifier  = 1.0,
			ball_size_mult      = 0.6, // Smaller ball

			// Gameplay
			win_score           = 3, // For easier testing
			single_player       = true,
			has_net             = false,
			net_height          = 0,

			// Visual - green court theme
			bg_color            = rl.Color{20, 30, 25, 255}, // Dark green-grey
			court_primary       = rl.Color{80, 140, 90, 255}, // Court green
			court_secondary     = rl.Color{60, 100, 70, 255}, // Darker green
			paddle_color        = rl.Color{220, 180, 100, 255}, // Wood/tan
			ball_color          = rl.Color{50, 50, 55, 255}, // Black rubber
			text_color          = rl.Color{200, 220, 180, 255}, // Light green
			accent_color        = rl.Color{255, 100, 100, 255}, // Red marker

			// UI
			show_rally_counter  = true,
			rally_threshold     = 20, // Squash has longer rallies
			countdown_enabled   = true,
			paddle_rounded      = false,

			// Paddle movement
			allow_x_movement    = true, // Can move forward/backward
			paddle_momentum     = 1.0, // No momentum
			paddle_acceleration = 1.0,

			// Goals
			has_goals           = false,
			goal_size           = 1.0,
		}

	case .TENNIS:
		return ModeConfig {
			name                = "TENNIS",
			description         = "Over the net competition",

			// Physics - ball scales and slows at net to simulate height
			ball_speed_mult     = 1.1,
			friction            = 1.0,
			wall_dampening      = 0.7,
			paddle_dampening    = 1.12,
			spin_dampening      = 0.8,
			spin_acceleration   = 1.5,
			ball_scale_at_net   = true, // Ball grows larger near net
			net_speed_modifier  = 0.85, // Ball slower at net (peak of arc)
			ball_size_mult      = 1.0,

			// Gameplay
			win_score           = 3, // For easier testing
			single_player       = false,
			has_net             = true,
			net_height          = f32(WIN_DIM.y), // Full screen height

			// Visual - grass court theme
			bg_color            = rl.Color{90, 140, 80, 255}, // Grass green
			court_primary       = rl.Color{200, 180, 140, 255}, // Clay/baseline
			court_secondary     = rl.Color{240, 240, 240, 255}, // White lines
			paddle_color        = rl.Color{255, 200, 100, 255}, // Racquet gold
			ball_color          = rl.Color{220, 255, 100, 255}, // Tennis ball yellow
			text_color          = rl.Color{255, 255, 255, 255}, // White
			accent_color        = rl.Color{100, 180, 255, 255}, // Sky blue

			// UI
			show_rally_counter  = true,
			rally_threshold     = 12,
			countdown_enabled   = true,
			paddle_rounded      = false,

			// Paddle movement
			allow_x_movement    = false,
			paddle_momentum     = 1.0, // No momentum
			paddle_acceleration = 1.0,

			// Goals
			has_goals           = false,
			goal_size           = 1.0,
		}
	}

	// Fallback to pong
	return getModeConfig(.PONG)
}

debugShow :: proc() {
	rl.DrawText(rl.TextFormat("%f", ball.vel), WIN_DIM.x - 150, WIN_DIM.y - 25, 20, rl.RED)
	rl.DrawFPS(25, WIN_DIM.y - 25)
}

drawLogo :: proc() {
	rl.DrawText("PONG", 20, 20, 40, theme.txt_light)
	rl.DrawText(
		"Loading...",
		WIN_DIM.x / 2 - rl.MeasureText("Loading...", 20) / 2,
		200,
		20,
		theme.txt_dark,
	)
}

drawTitle :: proc() {
	rl.DrawText("PONG", 20, 20, 40, theme.txt_light)
	rl.DrawText("Controls: W (up), S (down), SPACE (pause), X (quit)", 20, 120, 20, theme.txt_dark)
	rl.DrawText("Start game: ENTER", 20, 170, 20, theme.txt_dark)
	rl.DrawText("Rules: P1 on left, score 4 to win", 20, 220, 20, theme.txt_dark)
	rl.DrawText("Close game: ESC", 20, 270, 20, theme.txt_dark)
	rl.DrawText("DeBug info: hold B", 20, 320, 20, theme.txt_dark)
}

drawModeSelect :: proc(selected: GameMode) {
	// Title
	title_text: cstring = "SELECT GAME MODE"
	title_size: i32 = 40
	title_width := rl.MeasureText(title_text, title_size)
	rl.DrawText(title_text, WIN_DIM.x / 2 - title_width / 2, 20, title_size, theme.txt_dark)

	// Instructions
	inst_text: cstring = "< LEFT / RIGHT >    ENTER to select    ESC to quit"
	inst_size: i32 = 16
	inst_width := rl.MeasureText(inst_text, inst_size)
	rl.DrawText(inst_text, WIN_DIM.x / 2 - inst_width / 2, 360, inst_size, theme.txt_light)

	// Mode boxes in a row
	modes := [4]GameMode{.PONG, .AIR_HOCKEY, .SQUASH, .TENNIS}
	box_width: i32 = 130
	box_height: i32 = 180
	spacing: i32 = 10
	start_x := WIN_DIM.x / 2 - (box_width * 4 + spacing * 3) / 2
	start_y: i32 = 100

	for mode, i in modes {
		config := getModeConfig(mode)
		x := start_x + i32(i) * (box_width + spacing)
		y := start_y

		// Box background
		is_selected := mode == selected
		box_color := config.bg_color
		if is_selected {
			// Highlight selected with pulsing border
			border_thickness: i32 = 4
			rl.DrawRectangle(
				x - border_thickness,
				y - border_thickness,
				box_width + border_thickness * 2,
				box_height + border_thickness * 2,
				config.accent_color,
			)
			// Lift effect
			y -= 5
		}

		// Draw box
		rl.DrawRectangle(x, y, box_width, box_height, box_color)

		// Mode name
		name_size: i32 = 18
		name_lines := getWrappedText(config.name, name_size, box_width - 10)
		name_y := y + 10
		for line in name_lines {
			line_width := rl.MeasureText(line, name_size)
			rl.DrawText(
				line,
				x + box_width / 2 - line_width / 2,
				name_y,
				name_size,
				config.text_color,
			)
			name_y += name_size + 2
		}

		// Visual preview icon (simple representation)
		icon_y := y + 70
		icon_size: i32 = 40
		switch mode {
		case .PONG:
			// Two paddles
			rl.DrawRectangle(x + 20, icon_y, 8, 30, config.paddle_color)
			rl.DrawRectangle(x + box_width - 28, icon_y, 8, 30, config.paddle_color)
			rl.DrawCircle(x + box_width / 2, icon_y + 15, 6, config.ball_color)
		case .AIR_HOCKEY:
			// Circular mallets
			rl.DrawCircle(x + 30, icon_y + 15, 12, config.paddle_color)
			rl.DrawCircle(x + box_width - 30, icon_y + 15, 12, config.paddle_color)
			rl.DrawCircle(x + box_width / 2, icon_y + 15, 6, config.ball_color)
		case .SQUASH:
			// Paddle and wall
			rl.DrawRectangle(x + 20, icon_y, 8, 30, config.paddle_color)
			rl.DrawRectangle(x + box_width - 15, icon_y - 10, 5, 50, config.court_primary)
			rl.DrawCircle(x + 50, icon_y + 15, 6, config.ball_color)
		case .TENNIS:
			// Net in middle
			for net_i: i32 = 0; net_i < 40; net_i += 4 {
				rl.DrawPixel(x + box_width / 2, icon_y + net_i - 10, config.court_secondary)
			}
			rl.DrawRectangle(x + 15, icon_y + 5, 8, 20, config.paddle_color)
			rl.DrawRectangle(x + box_width - 23, icon_y + 5, 8, 20, config.paddle_color)
			rl.DrawCircle(x + box_width / 2 + 15, icon_y + 10, 5, config.ball_color)
		}

		// Description
		desc_size: i32 = 12
		desc_y := y + 120
		desc_lines := getWrappedText(config.description, desc_size, box_width - 10)
		for line in desc_lines {
			line_width := rl.MeasureText(line, desc_size)
			rl.DrawText(
				line,
				x + box_width / 2 - line_width / 2,
				desc_y,
				desc_size,
				config.text_color,
			)
			desc_y += desc_size + 2
		}

		// Win score indicator
		score_text := rl.TextFormat("First to %i", config.win_score)
		score_size: i32 = 11
		score_width := rl.MeasureText(score_text, score_size)
		rl.DrawText(
			score_text,
			x + box_width / 2 - score_width / 2,
			y + box_height - 20,
			score_size,
			config.accent_color,
		)
	}
}

// Helper to wrap text (simple version - splits on spaces)
getWrappedText :: proc(text: cstring, size: i32, max_width: i32) -> [dynamic]cstring {
	lines := make([dynamic]cstring)
	// For now, just return single line - proper text wrapping would be more complex
	append(&lines, text)
	return lines
}

drawGoals :: proc() {
	if !mode_config.has_goals {
		return
	}

	// Calculate goal dimensions
	goal_height := i32(f32(WIN_DIM.y) * mode_config.goal_size)
	goal_y_start := (WIN_DIM.y - goal_height) / 2
	goal_depth: i32 = 15

	// Left goal (P2 scores here)
	rl.DrawRectangle(0, goal_y_start, goal_depth, goal_height, mode_config.accent_color)
	// Left goal walls (top and bottom)
	rl.DrawRectangle(0, 0, goal_depth, goal_y_start, mode_config.court_primary)
	rl.DrawRectangle(
		0,
		goal_y_start + goal_height,
		goal_depth,
		WIN_DIM.y - (goal_y_start + goal_height),
		mode_config.court_primary,
	)

	// Right goal (P1 scores here)
	rl.DrawRectangle(
		WIN_DIM.x - goal_depth,
		goal_y_start,
		goal_depth,
		goal_height,
		mode_config.accent_color,
	)
	// Right goal walls (top and bottom)
	rl.DrawRectangle(
		WIN_DIM.x - goal_depth,
		0,
		goal_depth,
		goal_y_start,
		mode_config.court_primary,
	)
	rl.DrawRectangle(
		WIN_DIM.x - goal_depth,
		goal_y_start + goal_height,
		goal_depth,
		WIN_DIM.y - (goal_y_start + goal_height),
		mode_config.court_primary,
	)
}

drawNet :: proc() {
	if mode_config.has_net {
		// Tennis net - full height from top to bottom
		net_x := WIN_DIM.x / 2

		// Net post (thicker vertical line)
		rl.DrawRectangle(net_x - 3, 0, 6, WIN_DIM.y, mode_config.court_secondary)

		// Net mesh pattern across entire height
		for i: i32 = 0; i < WIN_DIM.y; i += 8 {
			for j: i32 = -15; j <= 15; j += 3 {
				rl.DrawPixel(net_x + j, i, mode_config.court_primary)
			}
		}
	} else if mode_config.allow_x_movement && !mode_config.single_player {
		// Air hockey: solid center line showing territory
		rl.DrawRectangle(WIN_DIM.x / 2 - 1, 0, 2, WIN_DIM.y, mode_config.court_secondary)
	} else {
		// Standard center line (dotted)
		for i: i32 = 0; i < WIN_DIM.y; i += 5 {
			rl.DrawPixel(WIN_DIM.x / 2, i, mode_config.court_primary)
		}
	}
}

drawScores :: proc(flashTimer: i32) {
	score_size: i32 = 60
	score_y: i32 = 30

	// P1 score - left side centered
	p1_text := rl.TextFormat("%i", p1.scr)
	p1_width := rl.MeasureText(p1_text, score_size)
	p1_x := WIN_DIM.x / 4 - p1_width / 2

	// P2 score - right side centered
	p2_text := rl.TextFormat("%i", p2.scr)
	p2_width := rl.MeasureText(p2_text, score_size)
	p2_x := (WIN_DIM.x * 3 / 4) - p2_width / 2

	// Flash effect when score changes
	score_color := theme.txt_dark
	if flashTimer > 0 {
		// Pulse using mode's accent color
		alpha := f32(flashTimer) / 30.0
		score_color = rl.ColorAlpha(mode_config.accent_color, alpha)
	}

	rl.DrawText(p1_text, p1_x, score_y, score_size, p1.col)
	rl.DrawText(p2_text, p2_x, score_y, score_size, p2.col)

	// Score separator
	rl.DrawText(
		"-",
		WIN_DIM.x / 2 - rl.MeasureText("-", 40) / 2,
		score_y + 10,
		40,
		theme.txt_light,
	)

	// Games won (match score) - display below point scores
	games_size: i32 = 20
	games_y: i32 = 100
	games_text := rl.TextFormat("Games: %i - %i", p1.games_won, p2.games_won)
	games_width := rl.MeasureText(games_text, games_size)
	rl.DrawText(games_text, WIN_DIM.x / 2 - games_width / 2, games_y, games_size, theme.txt_light)
}

playerControls :: proc() {
	target_vel := m.float2{0, 0}

	// Y-axis movement (always enabled)
	if rl.IsKeyDown(rl.KeyboardKey.W) {
		target_vel.y = -p1.spd
	}
	if rl.IsKeyDown(rl.KeyboardKey.S) {
		target_vel.y = p1.spd
	}

	// X-axis movement (forward/backward for squash)
	if mode_config.allow_x_movement {
		if rl.IsKeyDown(rl.KeyboardKey.A) {
			target_vel.x = -p1.spd
		}
		if rl.IsKeyDown(rl.KeyboardKey.D) {
			target_vel.x = p1.spd
		}
	}

	// Apply acceleration/momentum
	if mode_config.paddle_acceleration < 1.0 {
		// Air hockey style: accelerate when moving, slide when stopped
		if target_vel.x != 0 || target_vel.y != 0 {
			// Player is pressing keys - accelerate toward target
			p1.vel += (target_vel - p1.vel) * mode_config.paddle_acceleration
		} else {
			// No keys pressed - apply momentum/sliding friction
			p1.vel *= mode_config.paddle_momentum
		}
	} else {
		// Instant acceleration (no momentum)
		p1.vel = target_vel
	}

	// Update position
	p1.pos += p1.vel
}

// TODO: fix jerky movement here
cpuAI :: proc() {
	// Determine which side CPU is on (for side-switching support)
	p2_on_left := p2.pos.x < f32(WIN_DIM.x / 2)

	// Air hockey: CPU can move forward/backward and up/down
	if mode_config.allow_x_movement && mode_config.paddle_rounded {
		target_vel := m.float2{0, 0}

		// Y-axis movement - track ball
		if (p2.pos.y + p2.dim.y / 2) > ball.pos.y + 10 {
			target_vel.y = -p2.spd
		} else if (p2.pos.y + p2.dim.y / 2) < ball.pos.y - 10 {
			target_vel.y = p2.spd
		}

		// X-axis movement - move forward to intercept ball (logic depends on which side CPU is on)
		paddle_center_x := p2.pos.x + p2.dim.x

		if p2_on_left {
			// CPU is on LEFT side
			if ball.vel.x < 0 {
				// Ball coming toward CPU (moving left) - move forward to intercept
				if paddle_center_x < ball.pos.x - 40 {
					target_vel.x = p2.spd * 0.7 // Move forward (right)
				}
			} else {
				// Ball moving away (moving right) - retreat toward back of zone
				retreat_pos: f32 = 80.0
				if paddle_center_x > retreat_pos {
					target_vel.x = -p2.spd * 0.5 // Move back (left)
				}
			}
		} else {
			// CPU is on RIGHT side
			if ball.vel.x > 0 {
				// Ball coming toward CPU (moving right) - move forward to intercept
				if paddle_center_x > ball.pos.x + 40 {
					target_vel.x = -p2.spd * 0.7 // Move forward (left)
				}
			} else {
				// Ball moving away (moving left) - retreat toward back of zone
				retreat_pos := f32(WIN_DIM.x) - 80.0
				if paddle_center_x < retreat_pos {
					target_vel.x = p2.spd * 0.5 // Move back (right)
				}
			}
		}

		// Apply acceleration/momentum for air hockey
		if mode_config.paddle_acceleration < 1.0 {
			if target_vel.x != 0 || target_vel.y != 0 {
				p2.vel += (target_vel - p2.vel) * mode_config.paddle_acceleration
			} else {
				p2.vel *= mode_config.paddle_momentum
			}
		} else {
			p2.vel = target_vel
		}

		p2.pos += p2.vel
	} else {
		// Standard pong AI - only vertical movement
		// Ball velocity check depends on which side CPU is on
		ball_coming_toward_cpu := (p2_on_left && ball.vel.x < 0) || (!p2_on_left && ball.vel.x > 0)

		if (p2.pos.y + p2.dim.y / 2) > ball.pos.y && ball_coming_toward_cpu {
			p2.pos.y -= p2.spd
		} else if (p2.pos.y > ball.pos.y) && !ball_coming_toward_cpu {
			p2.pos.y -= p2.spd / 3 //idle
		} else if (p2.pos.y + p2.dim.y / 2) < ball.pos.y && ball_coming_toward_cpu {
			p2.pos.y += p2.spd
		} else if p2.pos.y < ball.pos.y && !ball_coming_toward_cpu {
			p2.pos.y += p2.spd / 3 //idle
		}
	}
}

setBoundaries :: proc() {
	// Determine which paddle is on which side based on current X position
	// This allows for side-switching between games
	p1_on_left := p1.pos.x < f32(WIN_DIM.x / 2)
	p2_on_left := p2.pos.x < f32(WIN_DIM.x / 2)

	// P1 X boundaries (if X movement allowed)
	if mode_config.allow_x_movement {
		if mode_config.single_player {
			// Squash: can move across most of court
			min_x: f32 = 15 // Past back wall
			max_x: f32 = f32(WIN_DIM.x) - 20 - p1.dim.x // Before front wall
			if p1.pos.x < min_x {
				p1.pos.x = min_x
				p1.vel.x = 0
			}
			if p1.pos.x > max_x {
				p1.pos.x = max_x
				p1.vel.x = 0
			}
		} else {
			// Air hockey: restricted to own half (dynamically determined)
			if p1_on_left {
				// P1 on left side
				min_x: f32 = 0
				max_x: f32 = f32(WIN_DIM.x / 2) - p1.dim.x - 5
				if p1.pos.x < min_x {
					p1.pos.x = min_x
					p1.vel.x = 0
				}
				if p1.pos.x > max_x {
					p1.pos.x = max_x
					p1.vel.x = 0
				}
			} else {
				// P1 on right side
				min_x: f32 = f32(WIN_DIM.x / 2) + 5
				max_x: f32 = f32(WIN_DIM.x) - p1.dim.x
				if p1.pos.x < min_x {
					p1.pos.x = min_x
					p1.vel.x = 0
				}
				if p1.pos.x > max_x {
					p1.pos.x = max_x
					p1.vel.x = 0
				}
			}
		}
	} else {
		// Standard X boundary - constrain to own starting side
		if p1_on_left {
			if p1.pos.x < 0 {
				p1.pos.x = 0
			}
		} else {
			if p1.pos.x > (f32(WIN_DIM.x) - p1.dim.x) {
				p1.pos.x = (f32(WIN_DIM.x) - p1.dim.x)
			}
		}
	}

	// P1 Y boundaries
	if p1.pos.y > (f32(WIN_DIM.y) - p1.dim.y) {
		p1.pos.y = (f32(WIN_DIM.y) - p1.dim.y)
		p1.vel.y = 0
	}
	if p1.pos.y < 0 {
		p1.pos.y = 0
		p1.vel.y = 0
	}

	// P2 boundaries (multiplayer only)
	if !mode_config.single_player {
		// P2 X boundaries (dynamically determined based on which side P2 is on)
		if mode_config.allow_x_movement {
			if p2_on_left {
				// P2 on left side
				min_x: f32 = 0
				max_x: f32 = f32(WIN_DIM.x / 2) - p2.dim.x - 5
				if p2.pos.x < min_x {
					p2.pos.x = min_x
				}
				if p2.pos.x > max_x {
					p2.pos.x = max_x
				}
			} else {
				// P2 on right side
				min_x: f32 = f32(WIN_DIM.x / 2) + 5
				max_x: f32 = f32(WIN_DIM.x) - p2.dim.x
				if p2.pos.x < min_x {
					p2.pos.x = min_x
				}
				if p2.pos.x > max_x {
					p2.pos.x = max_x
				}
			}
		} else {
			// Standard boundary - constrain to own side
			if p2_on_left {
				if p2.pos.x < 0 {
					p2.pos.x = 0
				}
			} else {
				if p2.pos.x > (f32(WIN_DIM.x) - p2.dim.x) {
					p2.pos.x = (f32(WIN_DIM.x) - p2.dim.x)
				}
			}
		}

		// P2 Y boundaries
		if p2.pos.y > (f32(WIN_DIM.y) - p2.dim.y) {
			p2.pos.y = (f32(WIN_DIM.y) - p2.dim.y)
		}
		if p2.pos.y < 0 {
			p2.pos.y = 0
		}
	}
}

// Get collision radius (mode-specific but not affected by visual scaling)
getBallCollisionRadius :: proc() -> f32 {
	return ball.r * mode_config.ball_size_mult
}

drawBall :: proc() {
	// Apply base mode size multiplier
	radius := ball.r * mode_config.ball_size_mult

	// Tennis: scale ball size based on distance from net (simulate height)
	if mode_config.ball_scale_at_net {
		center_x := f32(WIN_DIM.x / 2)
		dist_from_net := m.abs(ball.pos.x - center_x)
		max_dist := f32(WIN_DIM.x / 2)

		// Ball is larger (higher) when near net, smaller near paddles
		// Scale from 0.6x to 1.4x
		scale := 1.4 - (dist_from_net / max_dist) * 0.8
		radius *= scale
	}

	rl.DrawCircle(i32(ball.pos.x), i32(ball.pos.y), radius, ball.col)
}

moveBall :: proc() {
	// Calculate position-based speed modifier for tennis
	speed_mult := mode_config.ball_speed_mult

	if mode_config.net_speed_modifier != 1.0 {
		// Tennis: ball slows at net (center), normal speed at paddles (sides)
		center_x := f32(WIN_DIM.x / 2)
		dist_from_net := m.abs(ball.pos.x - center_x)
		max_dist := f32(WIN_DIM.x / 2)

		// Interpolate speed: 1.0 at paddles, net_speed_modifier at net
		t := 1.0 - (dist_from_net / max_dist) // 0 at paddles, 1 at net
		current_speed_mult := 1.0 + t * (mode_config.net_speed_modifier - 1.0)
		speed_mult *= current_speed_mult
	}

	// Apply mode-specific physics
	ball.pos += ball.vel * speed_mult

	// Apply friction (should be 1.0 for all modes = no friction)
	ball.vel *= mode_config.friction
}

drawEndScreen :: proc() {
	rl.DrawText("PONG", 20, 20, 40, theme.txt_light)
	rl.DrawText(rl.TextFormat("%s", winner), 20, 80, 30, theme.txt_dark)
	rl.DrawText("To play again press ENTER", 20, 140, 20, theme.txt_dark)
	rl.DrawText("Press ESC to quit", 20, 200, 20, theme.txt_dark)
}

trackWinner :: proc() {
	if p1.scr > p2.scr {
		winner = "Player 1 Wins!"
	} else if p2.scr > p1.scr {
		winner = "Player 2 Wins!"
	} else {
		winner = "It's a draw!"
	}
}

handlePaddleCollision :: proc(paddle: ^Paddle, strike_normal: rl.Sound, strike_spin: rl.Sound) {
	paddle.hit = true
	if rl.IsKeyDown(rl.KeyboardKey.W) || rl.IsKeyDown(rl.KeyboardKey.S) {
		ball.vel.x = -ball.vel.x * mode_config.spin_dampening
		ball.vel.y = -ball.vel.y * mode_config.spin_acceleration
		rl.PlaySound(strike_spin)
	} else {
		ball.vel.x = -ball.vel.x * mode_config.paddle_dampening
		rl.PlaySound(strike_normal)
	}
}

swapSides :: proc() {
	// Fully swap paddle data so player and CPU switch physical sides
	// This way the player (P1) moves to the right and controls from there
	// and CPU (P2) moves to the left

	// Swap positions (to opposite starting positions)
	p1.pos = m.float2{f32(P2_START_POS), f32(WIN_DIM.y / 2)}
	p2.pos = m.float2{f32(P1_START_POS), f32(WIN_DIM.y / 2)}

	// Reset velocities (don't swap, just reset)
	p1.vel = m.float2{0, 0}
	p2.vel = m.float2{0, 0}

	// Swap games won (this tracks the actual player/CPU, not the paddle object)
	p1.games_won, p2.games_won = p2.games_won, p1.games_won

	// Scores are already reset to 0-0 before calling this
	// Colors stay the same (P1 is always red, P2 is always blue)
	// Speed and dimensions stay the same
}

drawCountdown :: proc(timer: i32) {
	if !mode_config.countdown_enabled {
		return
	}

	countdown_num: i32
	if timer > 120 {
		countdown_num = 3
	} else if timer > 60 {
		countdown_num = 2
	} else if timer > 0 {
		countdown_num = 1
	} else {
		return
	}

	text := rl.TextFormat("%i", countdown_num)
	text_size: i32 = 120
	text_width := rl.MeasureText(text, text_size)

	// Pulsing effect using mode's accent color
	pulse := f32(timer % 60) / 60.0
	alpha := 0.3 + pulse * 0.7
	color := rl.ColorAlpha(mode_config.accent_color, alpha)

	rl.DrawText(text, WIN_DIM.x / 2 - text_width / 2, WIN_DIM.y / 2 - 60, text_size, color)
}

drawRallyCounter :: proc(rallyCount: i32) {
	if !mode_config.show_rally_counter || rallyCount <= 1 {
		return
	}

	text := rl.TextFormat("Rally: %i", rallyCount)
	text_size: i32 = 20
	text_width := rl.MeasureText(text, text_size)

	// Position in bottom center
	rl.DrawText(text, WIN_DIM.x / 2 - text_width / 2, WIN_DIM.y - 30, text_size, theme.txt_light)

	// Add excitement for long rallies (mode-specific threshold)
	threshold := mode_config.rally_threshold
	if rallyCount > threshold {
		excitement_text: cstring
		excitement_color := mode_config.accent_color
		if rallyCount > threshold * 2 {
			excitement_text = "AMAZING!"
		} else if rallyCount > threshold + (threshold / 2) {
			excitement_text = "INCREDIBLE!"
		} else {
			excitement_text = "Great Rally!"
		}

		excitement_width := rl.MeasureText(excitement_text, 25)
		rl.DrawText(
			excitement_text,
			WIN_DIM.x / 2 - excitement_width / 2,
			WIN_DIM.y / 2 - 30,
			25,
			excitement_color,
		)
	}
}
