package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const (
	maxNameRunes     = 32
	maxPlayerIDRunes = 64
)

// sanitizeName validates a player-supplied display name. It is stored and
// later rendered by other clients, so control characters are rejected rather
// than silently stripped.
func sanitizeName(raw string) (string, error) {
	name := strings.TrimSpace(raw)
	if name == "" {
		return "", errors.New("name is required")
	}
	if utf8.RuneCountInString(name) > maxNameRunes {
		return "", fmt.Errorf("name must be %d characters or fewer", maxNameRunes)
	}
	for _, r := range name {
		if unicode.IsControl(r) {
			return "", errors.New("name contains invalid characters")
		}
	}
	return name, nil
}

// sanitizePlayerID bounds the client-generated identity string. It is an
// opaque label used only for grouping a player's own entries.
func sanitizePlayerID(raw string) (string, error) {
	id := strings.TrimSpace(raw)
	if id == "" {
		return "", nil
	}
	if utf8.RuneCountInString(id) > maxPlayerIDRunes {
		return "", fmt.Errorf("playerId must be %d characters or fewer", maxPlayerIDRunes)
	}
	for _, r := range id {
		if unicode.IsControl(r) {
			return "", errors.New("playerId contains invalid characters")
		}
	}
	return id, nil
}

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
	if err := saveGameSession(r.Context(), game); err != nil {
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
	game, err := loadGameSession(r.Context(), req.ID)
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
		game.Moves++
		spawnTile(game)
		checkWin(game)
		if !canMove(game) {
			game.GameOver = true
		}

		// Save updated game session to DynamoDB
		if err := saveGameSession(r.Context(), game); err != nil {
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
	game, err := loadGameSession(r.Context(), id)
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

	// The score, move count and duration are deliberately NOT accepted from the
	// client — they are read back from the server's own record of the game.
	// Only the display name and the player's local identity come from the
	// request, and neither can influence ranking.
	type ScoreSubmission struct {
		GameID   string `json:"gameId"`
		PlayerID string `json:"playerId"`
		Name     string `json:"name"`
	}

	var submission ScoreSubmission
	if err := json.NewDecoder(r.Body).Decode(&submission); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if submission.GameID == "" {
		http.Error(w, "Game ID required", http.StatusBadRequest)
		return
	}

	name, err := sanitizeName(submission.Name)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	playerID, err := sanitizePlayerID(submission.PlayerID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	// Authoritative game state.
	game, err := loadGameSession(r.Context(), submission.GameID)
	if err != nil {
		log.Printf("Score submission for unknown game %s: %v", submission.GameID, err)
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}

	// A score is only meaningful once the game has actually ended, otherwise a
	// player could submit repeatedly and keep their best intermediate result.
	if !game.GameOver {
		http.Error(w, "Game is not over yet", http.StatusBadRequest)
		return
	}

	if game.Score <= 0 {
		http.Error(w, "Game has no score to submit", http.StatusBadRequest)
		return
	}

	// Claim the submission before writing, so two concurrent requests for the
	// same game cannot both land on the leaderboard.
	if err := claimSubmission(r.Context(), submission.GameID); err != nil {
		if errors.Is(err, errAlreadySubmitted) {
			http.Error(w, "Score already submitted for this game", http.StatusConflict)
			return
		}
		log.Printf("Failed to claim submission for game %s: %v", submission.GameID, err)
		http.Error(w, "Failed to save score", http.StatusInternalServerError)
		return
	}

	entry := LeaderboardEntry{
		PlayerID:  playerID,
		Name:      name,
		Score:     game.Score,
		Moves:     game.Moves,
		Duration:  int(time.Since(game.CreatedAt).Seconds()),
		Timestamp: time.Now(),
	}

	// Persist the score. AddScore returns the stored entry, which carries the
	// generated ID — the local `entry` above never receives it.
	stored, err := globalLeaderboard.AddScore(r.Context(), entry)
	if err != nil {
		// The claim is only meaningful if the score was actually recorded.
		releaseSubmission(r.Context(), submission.GameID)
		log.Printf("Failed to save score for %s: %v", name, err)
		http.Error(w, "Failed to save score", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"entry":   stored,
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
