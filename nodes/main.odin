package main

import "core:fmt"
import rl "vendor:raylib"

Node :: struct {
	id:               int,
	position:         rl.Vector2,
	value:            f32,
	input_connected:  bool,
	output_connected: bool,
}

Connection :: struct {
	from_node: int,
	to_node:   int,
}

node_count: f32 = 0

main :: proc() {
	rl.InitWindow(800, 600, "Node and Edges")
	rl.SetTargetFPS(60)

	nodes: [dynamic]Node
	connections: [dynamic]Connection

	selected_node: int = -1
	dragging: bool = false
	connecting: bool = false
	connect_start_node: int = -1

	for !rl.WindowShouldClose() {
		mouse_pos := rl.GetMousePosition()

		if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			// Check if clicking on a node
			for node, i in nodes {
				if rl.CheckCollisionPointCircle(mouse_pos, node.position, 30) {
					selected_node = i
					dragging = true
					break
				}
			}

			// If not clicking on a node, create a new node
			if selected_node == -1 {
				node_count += 1
				append(&nodes, Node{id = len(nodes), position = mouse_pos, value = node_count})
			}
		}

		if rl.IsMouseButtonReleased(rl.MouseButton.LEFT) {
			dragging = false
			selected_node = -1
		}

		if dragging && selected_node != -1 {
			nodes[selected_node].position = mouse_pos
		}

		// Handle connecting nodes
		if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
			for node, i in nodes {
				if rl.CheckCollisionPointCircle(mouse_pos, node.position, 30) {
					if !connecting {
						connect_start_node = i
						connecting = true
					} else {
						// Create a connection
						append(
							&connections,
							Connection{from_node = connect_start_node, to_node = i},
						)
						connecting = false
					}
					break
				}
			}
		}

		// Draw
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Draw connections
		for conn in connections {
			from_node := nodes[conn.from_node]
			to_node := nodes[conn.to_node]
			rl.DrawLineEx(from_node.position, to_node.position, 2, rl.WHITE)
		}

		// Draw nodes
		for node in nodes {
			rl.DrawCircleV(node.position, 30, rl.BLUE)
			rl.DrawText(
				rl.TextFormat("%0.2f", node.value),
				i32(node.position.x - 20),
				i32(node.position.y - 20),
				20,
				rl.WHITE,
			)
		}

		// Draw connecting line if in connecting mode
		if connecting {
			start_pos := nodes[connect_start_node].position
			rl.DrawLineEx(start_pos, mouse_pos, 2, rl.GREEN)
		}

		// Draw result
		if len(nodes) >= 2 && len(connections) > 0 {
			result: f32 = 0
			for conn in connections {
				result += nodes[conn.from_node].value + nodes[conn.to_node].value
			}
			rl.DrawText(rl.TextFormat("%f", result), 10, 10, 20, rl.WHITE)
		}

		rl.EndDrawing()
	}

	rl.CloseWindow()
}
