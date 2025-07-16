package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func newGameHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := generateID()
	game := &GameState{
		ID:        id,
		CreatedAt: time.Now(),
	}
	spawnTile(game)
	spawnTile(game)

	mu.Lock()
	games[id] = game
	mu.Unlock()

	log.Printf("New game created: %s", id)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(game)
}

func moveHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	type MoveRequest struct {
		ID        string `json:"id"`
		Direction string `json:"direction"`
	}
	var req MoveRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("Invalid move request: %v", err)
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	// Validate direction
	validDirections := map[string]bool{
		"up": true, "down": true, "left": true, "right": true,
	}
	if !validDirections[req.Direction] {
		http.Error(w, "Invalid direction", http.StatusBadRequest)
		return
	}

	mu.Lock()
	game, ok := games[req.ID]
	if !ok {
		mu.Unlock()
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}
	if game.GameOver {
		mu.Unlock()
		http.Error(w, "Game over", http.StatusBadRequest)
		return
	}

	moved := applyMove(game, req.Direction)
	if moved {
		spawnTile(game)
		checkWin(game)
		if !canMove(game) {
			game.GameOver = true
		}
		log.Printf("Move applied for game %s: %s (Score: %d)", req.ID, req.Direction, game.Score)
	}
	mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(game)
}

func stateHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, "Game ID required", http.StatusBadRequest)
		return
	}

	mu.Lock()
	game, ok := games[id]
	mu.Unlock()
	if !ok {
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(game)
}
