package main

import (
	"math/rand"
	"strconv"
	"time"
)

type GameState struct {
	ID        string    `json:"id"`
	Board     [4][4]int `json:"board"`
	Score     int       `json:"score"`
	GameOver  bool      `json:"gameOver"`
	Won       bool      `json:"won"`
	CreatedAt time.Time `json:"createdAt"`
}

// Removed in-memory storage - now using DynamoDB

func generateID() string {
	return time.Now().Format("20060102150405") + strconv.Itoa(rand.Intn(10000))
}

func spawnTile(game *GameState) {
	empty := [][2]int{}
	for r := 0; r < 4; r++ {
		for c := 0; c < 4; c++ {
			if game.Board[r][c] == 0 {
				empty = append(empty, [2]int{r, c})
			}
		}
	}
	if len(empty) == 0 {
		return
	}
	pos := empty[rand.Intn(len(empty))]
	val := 2
	if rand.Float64() < 0.1 {
		val = 4
	}
	game.Board[pos[0]][pos[1]] = val
}

func rotateRight(board *[4][4]int) {
	temp := [4][4]int{}
	for r := 0; r < 4; r++ {
		for c := 0; c < 4; c++ {
			temp[c][3-r] = board[r][c]
		}
	}
	*board = temp
}

func rotateLeft(board *[4][4]int) {
	temp := [4][4]int{}
	for r := 0; r < 4; r++ {
		for c := 0; c < 4; c++ {
			temp[3-c][r] = board[r][c]
		}
	}
	*board = temp
}

func rotate180(board *[4][4]int) {
	rotateRight(board)
	rotateRight(board)
}

func applyMove(game *GameState, dir string) bool {
	var moved bool
	var board [4][4]int

	copy(board[:], game.Board[:])

	switch dir {
	case "up":
		rotateLeft(&board)
	case "down":
		rotateRight(&board)
	case "right":
		rotate180(&board)
	}

	for i := 0; i < 4; i++ {
		temp := make([]int, 0, 4)
		for j := 0; j < 4; j++ {
			if board[i][j] != 0 {
				temp = append(temp, board[i][j])
			}
		}
		for j := 0; j < len(temp)-1; j++ {
			if temp[j] == temp[j+1] {
				temp[j] *= 2
				game.Score += temp[j]
				temp = append(temp[:j+1], temp[j+2:]...)
			}
		}
		for len(temp) < 4 {
			temp = append(temp, 0)
		}
		for j := 0; j < 4; j++ {
			if board[i][j] != temp[j] {
				moved = true
			}
			board[i][j] = temp[j]
		}
	}

	switch dir {
	case "up":
		rotateRight(&board)
	case "down":
		rotateLeft(&board)
	case "right":
		rotate180(&board)
	}

	game.Board = board
	return moved
}

func canMove(game *GameState) bool {
	for r := 0; r < 4; r++ {
		for c := 0; c < 4; c++ {
			if game.Board[r][c] == 0 {
				return true
			}
			if r < 3 && game.Board[r][c] == game.Board[r+1][c] {
				return true
			}
			if c < 3 && game.Board[r][c] == game.Board[r][c+1] {
				return true
			}
		}
	}
	return false
}

func checkWin(game *GameState) {
	if game.Won {
		return
	}
	for r := 0; r < 4; r++ {
		for c := 0; c < 4; c++ {
			if game.Board[r][c] == 2048 {
				game.Won = true
				return
			}
		}
	}
}

// Game cleanup is now handled by DynamoDB TTL
