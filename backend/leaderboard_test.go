package main

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"
)

// seedLeaderboard replaces the global leaderboard with a deterministic set of
// entries. The AWS clients are left nil so no network calls are made.
func seedLeaderboard(n int) {
	entries := make([]LeaderboardEntry, 0, n)
	for i := 0; i < n; i++ {
		entries = append(entries, LeaderboardEntry{
			ID:        fmt.Sprintf("id-%d", i),
			PlayerID:  fmt.Sprintf("player-%d", i),
			Name:      fmt.Sprintf("player %d", i),
			Score:     (i * 7) % 500,
			Timestamp: time.Unix(int64(1700000000+i), 0),
		})
	}
	globalLeaderboard = &Leaderboard{entries: entries}
}

// TestLeaderboardConcurrentReads exercises the three read paths concurrently.
// Each of them sorts the shared slice, so before the fix this fails under
// -race (and can panic inside sort.Slice).
func TestLeaderboardConcurrentReads(t *testing.T) {
	seedLeaderboard(200)

	const goroutines = 32
	var wg sync.WaitGroup

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			switch i % 3 {
			case 0:
				globalLeaderboard.GetTopScores(10)
			case 1:
				globalLeaderboard.GetPlayerRank(fmt.Sprintf("player-%d", i))
			case 2:
				globalLeaderboard.GetStats()
			}
		}(i)
	}

	wg.Wait()
}

// TestLeaderboardConcurrentReadWrite mixes writes in with the reads.
func TestLeaderboardConcurrentReadWrite(t *testing.T) {
	seedLeaderboard(100)

	var wg sync.WaitGroup
	for i := 0; i < 16; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			if _, err := globalLeaderboard.AddScore(context.Background(), LeaderboardEntry{
				PlayerID: fmt.Sprintf("new-%d", i),
				Name:     fmt.Sprintf("new player %d", i),
				Score:    i * 13,
			}); err != nil {
				t.Errorf("AddScore: %v", err)
			}
		}(i)

		wg.Add(1)
		go func() {
			defer wg.Done()
			globalLeaderboard.GetTopScores(10)
		}()
	}

	wg.Wait()
}

// TestGetTopScoresOrdering pins the documented ordering: score descending,
// ties broken by the earlier timestamp.
func TestGetTopScoresOrdering(t *testing.T) {
	globalLeaderboard = &Leaderboard{entries: []LeaderboardEntry{
		{ID: "a", PlayerID: "a", Name: "a", Score: 100, Timestamp: time.Unix(2000, 0)},
		{ID: "b", PlayerID: "b", Name: "b", Score: 300, Timestamp: time.Unix(1000, 0)},
		{ID: "c", PlayerID: "c", Name: "c", Score: 300, Timestamp: time.Unix(500, 0)},
		{ID: "d", PlayerID: "d", Name: "d", Score: 200, Timestamp: time.Unix(1500, 0)},
	}}

	got := globalLeaderboard.GetTopScores(4)
	want := []string{"c", "b", "d", "a"}

	if len(got) != len(want) {
		t.Fatalf("got %d entries, want %d", len(got), len(want))
	}
	for i := range want {
		if got[i].ID != want[i] {
			t.Errorf("position %d: got %q, want %q", i, got[i].ID, want[i])
		}
	}
}

// TestGetTopScoresLimit checks the limit is honoured and does not over-read.
func TestGetTopScoresLimit(t *testing.T) {
	seedLeaderboard(50)

	if got := globalLeaderboard.GetTopScores(5); len(got) != 5 {
		t.Errorf("limit 5: got %d entries", len(got))
	}
	if got := globalLeaderboard.GetTopScores(500); len(got) != 50 {
		t.Errorf("limit above size: got %d entries, want 50", len(got))
	}
}
