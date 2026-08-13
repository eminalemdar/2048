package main

import (
	"testing"
)

// board is a readability helper: tests declare boards as literals so the
// expected result is visible as a grid rather than a flat list.
type board = [4][4]int

func gameWith(b board) *GameState {
	return &GameState{Board: b}
}

func assertBoard(t *testing.T, got, want board) {
	t.Helper()
	if got != want {
		t.Errorf("board mismatch\ngot:\n%s\nwant:\n%s", formatBoard(got), formatBoard(want))
	}
}

func formatBoard(b board) string {
	out := ""
	for _, row := range b {
		for _, cell := range row {
			out += "\t" + itoa(cell)
		}
		out += "\n"
	}
	return out
}

func itoa(n int) string {
	if n == 0 {
		return "."
	}
	digits := ""
	for n > 0 {
		digits = string(rune('0'+n%10)) + digits
		n /= 10
	}
	return digits
}

// TestApplyMoveDirections covers sliding and merging in all four directions.
// The expectations encode standard 2048 rules, independent of how applyMove
// happens to implement them (it rotates the board and always merges "left").
func TestApplyMoveDirections(t *testing.T) {
	tests := []struct {
		name      string
		start     board
		dir       string
		want      board
		wantScore int
		wantMoved bool
	}{
		{
			name: "left: slide without merging",
			start: board{
				{0, 0, 2, 0},
				{0, 4, 0, 0},
				{0, 0, 0, 8},
				{0, 0, 0, 0},
			},
			dir: "left",
			want: board{
				{2, 0, 0, 0},
				{4, 0, 0, 0},
				{8, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 0,
			wantMoved: true,
		},
		{
			name: "left: merge a pair, scoring the merged value",
			start: board{
				{2, 2, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "left",
			want: board{
				{4, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "left: three equal tiles merge only the leading pair",
			start: board{
				{2, 2, 2, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "left",
			want: board{
				{4, 2, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "left: four equal tiles merge into two pairs",
			start: board{
				{2, 2, 2, 2},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "left",
			want: board{
				{4, 4, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 8,
			wantMoved: true,
		},
		{
			name: "left: a merged tile does not merge again in the same move",
			start: board{
				{4, 2, 2, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "left",
			want: board{
				{4, 4, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "right: tiles pack against the right edge",
			start: board{
				{2, 2, 0, 0},
				{0, 8, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "right",
			want: board{
				{0, 0, 0, 4},
				{0, 0, 0, 8},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "up: a column merges toward the top",
			start: board{
				{0, 0, 0, 0},
				{2, 0, 0, 0},
				{2, 0, 0, 0},
				{0, 0, 16, 0},
			},
			dir: "up",
			want: board{
				{4, 0, 16, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "down: a column merges toward the bottom",
			start: board{
				{2, 0, 16, 0},
				{2, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			dir: "down",
			want: board{
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
				{4, 0, 16, 0},
			},
			wantScore: 4,
			wantMoved: true,
		},
		{
			name: "left: already packed, nothing moves",
			start: board{
				{2, 4, 8, 16},
				{4, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 128},
			},
			dir: "left",
			want: board{
				{2, 4, 8, 16},
				{4, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 128},
			},
			wantScore: 0,
			wantMoved: false,
		},
		{
			name: "up: independent columns merge independently",
			start: board{
				{2, 4, 0, 0},
				{2, 4, 0, 0},
				{2, 4, 0, 0},
				{2, 4, 0, 0},
			},
			dir: "up",
			want: board{
				{4, 8, 0, 0},
				{4, 8, 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0},
			},
			wantScore: 24, // 4+4 from the twos, 8+8 from the fours
			wantMoved: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			game := gameWith(tc.start)

			moved := applyMove(game, tc.dir)

			assertBoard(t, game.Board, tc.want)
			if moved != tc.wantMoved {
				t.Errorf("moved = %v, want %v", moved, tc.wantMoved)
			}
			if game.Score != tc.wantScore {
				t.Errorf("score = %d, want %d", game.Score, tc.wantScore)
			}
		})
	}
}

// TestApplyMoveScoreAccumulates checks the score is added to across moves
// rather than replaced.
func TestApplyMoveScoreAccumulates(t *testing.T) {
	game := gameWith(board{
		{2, 2, 0, 0},
		{2, 2, 0, 0},
		{0, 0, 0, 0},
		{0, 0, 0, 0},
	})

	applyMove(game, "left") // two pairs merge -> +8
	if game.Score != 8 {
		t.Fatalf("after first move score = %d, want 8", game.Score)
	}

	applyMove(game, "up") // the two 4s merge -> +8
	if game.Score != 16 {
		t.Errorf("after second move score = %d, want 16", game.Score)
	}
}

// TestApplyMoveRejectsNoOp confirms a move that changes nothing reports false,
// which is what stops the caller from spawning a new tile.
func TestApplyMoveNoOpLeavesBoardUntouched(t *testing.T) {
	start := board{
		{2, 0, 0, 0},
		{0, 0, 0, 0},
		{0, 0, 0, 0},
		{0, 0, 0, 0},
	}
	game := gameWith(start)

	if moved := applyMove(game, "left"); moved {
		t.Error("moved = true for a board already packed left")
	}
	assertBoard(t, game.Board, start)
}

func TestRotations(t *testing.T) {
	original := board{
		{1, 2, 3, 4},
		{5, 6, 7, 8},
		{9, 10, 11, 12},
		{13, 14, 15, 16},
	}

	t.Run("right then left is identity", func(t *testing.T) {
		b := original
		rotateRight(&b)
		rotateLeft(&b)
		assertBoard(t, b, original)
	})

	t.Run("180 twice is identity", func(t *testing.T) {
		b := original
		rotate180(&b)
		rotate180(&b)
		assertBoard(t, b, original)
	})

	t.Run("right moves the top row to the right column", func(t *testing.T) {
		b := original
		rotateRight(&b)
		assertBoard(t, b, board{
			{13, 9, 5, 1},
			{14, 10, 6, 2},
			{15, 11, 7, 3},
			{16, 12, 8, 4},
		})
	})

	t.Run("four right rotations return to the start", func(t *testing.T) {
		b := original
		for i := 0; i < 4; i++ {
			rotateRight(&b)
		}
		assertBoard(t, b, original)
	})
}

func TestCanMove(t *testing.T) {
	tests := []struct {
		name  string
		board board
		want  bool
	}{
		{
			name: "empty cell means a move is possible",
			board: board{
				{2, 4, 8, 16},
				{4, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 0},
			},
			want: true,
		},
		{
			name: "full board with no equal neighbours is stuck",
			board: board{
				{2, 4, 8, 16},
				{4, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 128},
			},
			want: false,
		},
		{
			name: "full board with a horizontal pair can still move",
			board: board{
				{2, 2, 8, 16},
				{4, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 128},
			},
			want: true,
		},
		{
			name: "full board with a vertical pair can still move",
			board: board{
				{2, 4, 8, 16},
				{2, 8, 16, 32},
				{8, 16, 32, 64},
				{16, 32, 64, 128},
			},
			want: true,
		},
		{
			name:  "an empty board can move",
			board: board{},
			want:  true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := canMove(gameWith(tc.board)); got != tc.want {
				t.Errorf("canMove() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestCheckWin(t *testing.T) {
	t.Run("sets Won when a 2048 tile exists", func(t *testing.T) {
		game := gameWith(board{
			{0, 0, 0, 0},
			{0, 2048, 0, 0},
			{0, 0, 0, 0},
			{0, 0, 0, 0},
		})
		checkWin(game)
		if !game.Won {
			t.Error("Won = false, want true")
		}
	})

	t.Run("leaves Won false below 2048", func(t *testing.T) {
		game := gameWith(board{
			{1024, 512, 0, 0},
			{0, 0, 0, 0},
			{0, 0, 0, 0},
			{0, 0, 0, 0},
		})
		checkWin(game)
		if game.Won {
			t.Error("Won = true, want false")
		}
	})

	t.Run("stays won once won", func(t *testing.T) {
		game := gameWith(board{})
		game.Won = true
		checkWin(game)
		if !game.Won {
			t.Error("Won was reset to false")
		}
	})
}

func TestSpawnTile(t *testing.T) {
	t.Run("fills the only empty cell with a 2 or a 4", func(t *testing.T) {
		game := gameWith(board{
			{2, 4, 8, 16},
			{4, 8, 16, 32},
			{8, 16, 32, 64},
			{16, 32, 64, 0},
		})

		spawnTile(game)

		got := game.Board[3][3]
		if got != 2 && got != 4 {
			t.Errorf("spawned value = %d, want 2 or 4", got)
		}
	})

	t.Run("is a no-op on a full board", func(t *testing.T) {
		full := board{
			{2, 4, 8, 16},
			{4, 8, 16, 32},
			{8, 16, 32, 64},
			{16, 32, 64, 128},
		}
		game := gameWith(full)

		spawnTile(game)

		assertBoard(t, game.Board, full)
	})

	t.Run("adds exactly one tile", func(t *testing.T) {
		game := gameWith(board{})

		for want := 1; want <= 16; want++ {
			spawnTile(game)
			if got := countNonZero(game.Board); got != want {
				t.Fatalf("after %d spawns the board holds %d tiles", want, got)
			}
		}
	})

	t.Run("only ever spawns 2 or 4", func(t *testing.T) {
		for i := 0; i < 500; i++ {
			game := gameWith(board{})
			spawnTile(game)
			for _, row := range game.Board {
				for _, cell := range row {
					if cell != 0 && cell != 2 && cell != 4 {
						t.Fatalf("spawned an unexpected value: %d", cell)
					}
				}
			}
		}
	})
}

func countNonZero(b board) int {
	n := 0
	for _, row := range b {
		for _, cell := range row {
			if cell != 0 {
				n++
			}
		}
	}
	return n
}

// TestGameReachesTerminalState plays a full game with a fixed move cycle and
// asserts it ends in a genuinely stuck position — the same end condition the
// HTTP layer relies on to accept a score submission.
func TestGameReachesTerminalState(t *testing.T) {
	game := &GameState{}
	spawnTile(game)
	spawnTile(game)

	dirs := []string{"left", "up", "right", "down"}
	for i := 0; i < 5000; i++ {
		if applyMove(game, dirs[i%len(dirs)]) {
			spawnTile(game)
		}
		if !canMove(game) {
			if countNonZero(game.Board) != 16 {
				t.Fatalf("game over with empty cells remaining:\n%s", formatBoard(game.Board))
			}
			if game.Score <= 0 {
				t.Errorf("finished with score %d, expected merges to have scored", game.Score)
			}
			return
		}
	}
	t.Fatal("game did not reach a terminal state within 5000 moves")
}
