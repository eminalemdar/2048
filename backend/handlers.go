package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
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

	// Save game session to DynamoDB
	if err := saveGameSession(game); err != nil {
		log.Printf("Failed to save game session: %v", err)
		http.Error(w, "Failed to create game", http.StatusInternalServerError)
		return
	}

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

	// Load game session from DynamoDB
	game, err := loadGameSession(req.ID)
	if err != nil {
		log.Printf("Game not found: %s, error: %v", req.ID, err)
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}

	if game.GameOver {
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

		// Save updated game session to DynamoDB
		if err := saveGameSession(game); err != nil {
			log.Printf("Failed to save game session after move: %v", err)
			http.Error(w, "Failed to save game state", http.StatusInternalServerError)
			return
		}

		log.Printf("Move applied for game %s: %s (Score: %d)", req.ID, req.Direction, game.Score)
	}

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

	// Load game session from DynamoDB
	game, err := loadGameSession(id)
	if err != nil {
		log.Printf("Game not found: %s, error: %v", id, err)
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(game)
}

// Leaderboard Handlers

func submitScoreHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	type ScoreSubmission struct {
		PlayerID string `json:"playerId"`
		Name     string `json:"name"`
		Score    int    `json:"score"`
		Duration int    `json:"duration"`
		Moves    int    `json:"moves"`
	}

	var submission ScoreSubmission
	if err := json.NewDecoder(r.Body).Decode(&submission); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate submission
	if submission.Name == "" || submission.Score <= 0 {
		http.Error(w, "Invalid submission data", http.StatusBadRequest)
		return
	}

	// Create leaderboard entry
	entry := LeaderboardEntry{
		PlayerID:  submission.PlayerID,
		Name:      submission.Name,
		Score:     submission.Score,
		Duration:  submission.Duration,
		Moves:     submission.Moves,
		Timestamp: time.Now(),
	}

	// Add to leaderboard
	globalLeaderboard.AddScore(entry)

	// Return the entry with generated ID
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"entry":   entry,
	})
}

func leaderboardHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Get limit from query parameter (default: 10)
	limitStr := r.URL.Query().Get("limit")
	limit := 10
	if limitStr != "" {
		if parsedLimit, err := strconv.Atoi(limitStr); err == nil && parsedLimit > 0 {
			limit = parsedLimit
		}
	}

	// Get top scores (will load fresh data from DynamoDB)
	topScores := globalLeaderboard.GetTopScores(limit)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"scores": topScores,
		"total":  len(topScores),
	})
}

func playerRankHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	playerID := r.URL.Query().Get("playerId")
	if playerID == "" {
		http.Error(w, "Player ID required", http.StatusBadRequest)
		return
	}

	rank, entry := globalLeaderboard.GetPlayerRank(playerID)
	if rank == -1 {
		http.Error(w, "Player not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"rank":  rank,
		"entry": entry,
	})
}

func statsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	stats := globalLeaderboard.GetStats()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(stats)
}
