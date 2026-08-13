package main

import (
	"context"
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

const (
	// maxCachedEntries bounds the in-memory copy of the leaderboard.
	maxCachedEntries = 1000

	// leaderboardCacheTTL is how long a loaded snapshot is reused before
	// hitting persistent storage again. Every read path refreshes, so without
	// a TTL each request would trigger a full DynamoDB Scan.
	leaderboardCacheTTL = 5 * time.Second
)

type Leaderboard struct {
	entries []LeaderboardEntry
	mu      sync.RWMutex

	// loadMu guards the refresh cycle. It is deliberately separate from mu so
	// that a slow reload never blocks readers of the current snapshot.
	loadMu     sync.Mutex
	lastLoaded time.Time
}

var globalLeaderboard = &Leaderboard{
	entries: make([]LeaderboardEntry, 0),
}

// AddScore persists a score and returns the stored entry.
//
// The write is synchronous on purpose: the caller reports success to the
// player, so it must not claim success for a score that was never stored.
func (l *Leaderboard) AddScore(ctx context.Context, entry LeaderboardEntry) (LeaderboardEntry, error) {
	if entry.ID == "" {
		entry.ID = generateID()
	}
	if entry.Timestamp.IsZero() {
		entry.Timestamp = time.Now()
	}

	if dynamodbClient != nil {
		if err := l.saveEntryToDynamoDB(ctx, entry); err != nil {
			return LeaderboardEntry{}, err
		}
		// Make the new score visible to the next read rather than waiting out
		// the cache TTL, so a player sees their own submission immediately.
		l.invalidateCache()
	}

	l.mu.Lock()
	l.entries = append(l.entries, entry)
	if len(l.entries) > maxCachedEntries {
		sortEntries(l.entries)
		l.entries = l.entries[:maxCachedEntries]
	}
	l.mu.Unlock()

	// Refresh the S3 snapshot so the backup reflects the score just accepted.
	// Synchronous on purpose: an orphaned goroutine could outlive the process
	// during a rolling update and lose the write silently.
	l.backupToS3(ctx)

	log.Printf("New score added: %s - %d points", entry.Name, entry.Score)
	return entry, nil
}

// GetTopScores returns the top N scores.
func (l *Leaderboard) GetTopScores(limit int) []LeaderboardEntry {
	l.refreshIfStale()

	sorted := l.sortedSnapshot()
	if limit > len(sorted) {
		limit = len(sorted)
	}
	if limit < 0 {
		limit = 0
	}
	return sorted[:limit]
}

// GetPlayerRank returns the 1-based rank of a specific player, or -1.
func (l *Leaderboard) GetPlayerRank(playerID string) (int, *LeaderboardEntry) {
	l.refreshIfStale()

	sorted := l.sortedSnapshot()
	for i := range sorted {
		if sorted[i].PlayerID == playerID {
			entry := sorted[i]
			return i + 1, &entry
		}
	}

	return -1, nil
}

// GetStats returns leaderboard statistics
func (l *Leaderboard) GetStats() map[string]interface{} {
	l.refreshIfStale()

	sorted := l.sortedSnapshot()
	if len(sorted) == 0 {
		return map[string]interface{}{
			"totalPlayers": 0,
			"totalGames":   0,
			"highestScore": 0,
			"averageScore": 0,
		}
	}

	totalScore := 0
	playerMap := make(map[string]bool)

	for _, entry := range sorted {
		totalScore += entry.Score
		playerMap[entry.PlayerID] = true
	}

	return map[string]interface{}{
		"totalPlayers": len(playerMap),
		"totalGames":   len(sorted),
		"highestScore": sorted[0].Score,
		"averageScore": totalScore / len(sorted),
	}
}

// sortedSnapshot returns a sorted copy of the entries.
//
// The copy matters: sorting reorders the slice in place, so sorting the shared
// entries under a read lock would let concurrent readers mutate the same
// backing array at once. Snapshot under the lock, sort after releasing it.
func (l *Leaderboard) sortedSnapshot() []LeaderboardEntry {
	l.mu.RLock()
	snapshot := make([]LeaderboardEntry, len(l.entries))
	copy(snapshot, l.entries)
	l.mu.RUnlock()

	sortEntries(snapshot)
	return snapshot
}

// refreshIfStale reloads from persistent storage at most once per
// leaderboardCacheTTL. All read paths call this so replicas converge on the
// same data without issuing a full table Scan for every request.
func (l *Leaderboard) refreshIfStale() {
	l.loadMu.Lock()
	defer l.loadMu.Unlock()

	if !l.lastLoaded.IsZero() && time.Since(l.lastLoaded) < leaderboardCacheTTL {
		return
	}

	l.loadFromPersistentStorage()
	l.lastLoaded = time.Now()
}

// invalidateCache forces the next read to reload from persistent storage.
func (l *Leaderboard) invalidateCache() {
	l.loadMu.Lock()
	l.lastLoaded = time.Time{}
	l.loadMu.Unlock()
}

// sortEntries sorts a slice by score (descending), ties broken by the earlier
// timestamp. It operates on the caller's slice, never on shared state.
func sortEntries(entries []LeaderboardEntry) {
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Score == entries[j].Score {
			return entries[i].Timestamp.Before(entries[j].Timestamp)
		}
		return entries[i].Score > entries[j].Score
	})
}

// backupToS3 writes a snapshot of the leaderboard to S3.
//
// Best effort: a failed backup is logged but never fails the caller, because
// the score is already durable in DynamoDB by that point. Returns immediately
// when the backup is not configured.
func (l *Leaderboard) backupToS3(ctx context.Context) {
	if !s3BackupEnabled() {
		return
	}

	// Snapshot under the lock, then upload without holding it.
	l.mu.RLock()
	snapshot := make([]LeaderboardEntry, len(l.entries))
	copy(snapshot, l.entries)
	l.mu.RUnlock()

	sortEntries(snapshot)

	if err := l.saveToS3(ctx, snapshot); err != nil {
		log.Printf("S3 backup failed (the score is still saved in DynamoDB): %v", err)
	}
}

// loadFromPersistentStorage loads the leaderboard, preferring DynamoDB and
// falling back to the S3 snapshot.
//
// The fallback triggers on an actual read failure, not merely on DynamoDB
// being unconfigured — that is what makes S3 useful during a DynamoDB outage
// rather than only in a DynamoDB-less deployment.
func (l *Leaderboard) loadFromPersistentStorage() {
	if dynamodbClient != nil {
		if err := l.loadFromDynamoDB(); err == nil {
			return
		} else {
			log.Printf("DynamoDB read failed, trying the S3 fallback: %v", err)
		}
	}

	if s3Client != nil {
		if err := l.loadFromS3(); err == nil {
			return
		} else {
			log.Printf("S3 fallback read failed: %v", err)
		}
	}

	log.Println("No leaderboard source available; serving whatever is cached in memory")
}

// Count returns the number of entries currently held in memory.
func (l *Leaderboard) Count() int {
	l.mu.RLock()
	defer l.mu.RUnlock()
	return len(l.entries)
}

// Initialize leaderboard on startup
func initLeaderboard() {
	log.Println("Initializing leaderboard...")
	globalLeaderboard.refreshIfStale()
	log.Printf("Leaderboard initialized with %d entries", globalLeaderboard.Count())
}
