package main

import (
	"encoding/json"
	"log"
	"sort"
	"sync"
	"time"
)

type LeaderboardEntry struct {
	ID        string    `json:"id"`
	PlayerID  string    `json:"playerId"`
	Name      string    `json:"name"`
	Score     int       `json:"score"`
	Timestamp time.Time `json:"timestamp"`
	Duration  int       `json:"duration"` // Game duration in seconds
	Moves     int       `json:"moves"`    // Number of moves made
}

type Leaderboard struct {
	entries []LeaderboardEntry
	mu      sync.RWMutex
}

var globalLeaderboard = &Leaderboard{
	entries: make([]LeaderboardEntry, 0),
}

// AddScore adds a new score to the leaderboard
func (l *Leaderboard) AddScore(entry LeaderboardEntry) {
	l.mu.Lock()
	defer l.mu.Unlock()

	// Generate ID if not provided
	if entry.ID == "" {
		entry.ID = generateID()
	}

	// Set timestamp if not provided
	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now()
	}

	l.entries = append(l.entries, entry)

	// Keep only top 1000 scores to prevent memory issues
	if len(l.entries) > 1000 {
		l.sortEntries()
		l.entries = l.entries[:1000]
	}

	// Save to persistent storage
	go l.saveToPersistentStorage()

	log.Printf("New score added: %s - %d points", entry.Name, entry.Score)
}

// GetTopScores returns the top N scores
func (l *Leaderboard) GetTopScores(limit int) []LeaderboardEntry {
	l.mu.RLock()
	defer l.mu.RUnlock()

	l.sortEntries()

	if limit > len(l.entries) {
		limit = len(l.entries)
	}

	result := make([]LeaderboardEntry, limit)
	copy(result, l.entries[:limit])
	return result
}

// GetPlayerRank returns the rank of a specific player
func (l *Leaderboard) GetPlayerRank(playerID string) (int, *LeaderboardEntry) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	l.sortEntries()

	for i, entry := range l.entries {
		if entry.PlayerID == playerID {
			return i + 1, &entry
		}
	}

	return -1, nil
}

// GetStats returns leaderboard statistics
func (l *Leaderboard) GetStats() map[string]interface{} {
	l.mu.RLock()
	defer l.mu.RUnlock()

	if len(l.entries) == 0 {
		return map[string]interface{}{
			"totalPlayers": 0,
			"totalGames":   0,
			"highestScore": 0,
			"averageScore": 0,
		}
	}

	l.sortEntries()

	totalScore := 0
	playerMap := make(map[string]bool)

	for _, entry := range l.entries {
		totalScore += entry.Score
		playerMap[entry.PlayerID] = true
	}

	return map[string]interface{}{
		"totalPlayers": len(playerMap),
		"totalGames":   len(l.entries),
		"highestScore": l.entries[0].Score,
		"averageScore": totalScore / len(l.entries),
	}
}

// sortEntries sorts entries by score (descending)
func (l *Leaderboard) sortEntries() {
	sort.Slice(l.entries, func(i, j int) bool {
		if l.entries[i].Score == l.entries[j].Score {
			// If scores are equal, sort by timestamp (earlier is better)
			return l.entries[i].Timestamp.Before(l.entries[j].Timestamp)
		}
		return l.entries[i].Score > l.entries[j].Score
	})
}

// saveToPersistentStorage saves leaderboard to configured storage
func (l *Leaderboard) saveToPersistentStorage() {
	// Try DynamoDB first (primary storage)
	if dynamodbClient != nil {
		l.saveToDynamoDB()
	}

	// If S3 is configured, also save there (backup)
	if s3Client != nil {
		l.saveToS3()
	}

	// JSON file as fallback
	l.saveToJSON()
}

// saveToJSON saves leaderboard to a JSON file (fallback storage)
func (l *Leaderboard) saveToJSON() {
	_, err := json.MarshalIndent(l.entries, "", "  ")
	if err != nil {
		log.Printf("Error marshaling leaderboard: %v", err)
		return
	}

	// In a real implementation, you'd write to a file
	// For now, we'll just log that we would save
	log.Printf("Would save %d entries to JSON storage", len(l.entries))
}

// loadFromPersistentStorage loads leaderboard from configured storage
func (l *Leaderboard) loadFromPersistentStorage() {
	// Try to load from primary storage (DynamoDB, then S3, then JSON)
	if dynamodbClient != nil {
		l.loadFromDynamoDB()
	} else if s3Client != nil {
		l.loadFromS3()
	} else {
		l.loadFromJSON()
	}
}

// loadFromJSON loads leaderboard from JSON file
func (l *Leaderboard) loadFromJSON() {
	// Implementation for loading from JSON file
	log.Println("Loading leaderboard from JSON storage")
}

// Initialize leaderboard on startup
func initLeaderboard() {
	log.Println("Initializing leaderboard...")
	globalLeaderboard.loadFromPersistentStorage()
	log.Printf("Leaderboard initialized with %d entries", len(globalLeaderboard.entries))
}
