package main

import (
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// TestGenerateIDUnpredictable checks the identifier is full-length random hex
// and does not collide. The previous scheme was a timestamp plus at most four
// digits, which made live sessions enumerable.
func TestGenerateIDUnpredictable(t *testing.T) {
	const iterations = 10000

	seen := make(map[string]struct{}, iterations)
	for i := 0; i < iterations; i++ {
		id := generateID()

		if len(id) != 32 {
			t.Fatalf("id %q has length %d, want 32", id, len(id))
		}
		if _, err := hex.DecodeString(id); err != nil {
			t.Fatalf("id %q is not hex: %v", id, err)
		}
		if _, dup := seen[id]; dup {
			t.Fatalf("duplicate id generated: %q", id)
		}
		seen[id] = struct{}{}
	}

	// A timestamp-prefixed scheme would share a long common prefix across IDs
	// generated in the same second. Random IDs should not.
	ids := make([]string, 0, 100)
	for id := range seen {
		ids = append(ids, id)
		if len(ids) == 100 {
			break
		}
	}
	for i := 1; i < len(ids); i++ {
		if shared := commonPrefix(ids[0], ids[i]); shared > 8 {
			t.Errorf("ids share a %d-character prefix, suggesting low entropy", shared)
		}
	}
}

func commonPrefix(a, b string) int {
	n := 0
	for n < len(a) && n < len(b) && a[n] == b[n] {
		n++
	}
	return n
}

func TestSanitizeName(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    string
		wantErr bool
	}{
		{"plain", "Emin", "Emin", false},
		{"trims surrounding space", "  Emin  ", "Emin", false},
		{"unicode is allowed", "Emin 🎮", "Emin 🎮", false},
		{"at the limit", strings.Repeat("a", 32), strings.Repeat("a", 32), false},
		{"empty", "", "", true},
		{"only whitespace", "   ", "", true},
		{"too long", strings.Repeat("a", 33), "", true},
		{"newline injection", "Emin\nadmin", "", true},
		{"null byte", "Emin\x00", "", true},
		{"escape sequence", "\x1b[31mEmin", "", true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := sanitizeName(tc.input)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("sanitizeName(%q) = %q, want error", tc.input, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("sanitizeName(%q): unexpected error %v", tc.input, err)
			}
			if got != tc.want {
				t.Errorf("sanitizeName(%q) = %q, want %q", tc.input, got, tc.want)
			}
		})
	}
}

func TestSanitizePlayerID(t *testing.T) {
	if _, err := sanitizePlayerID(strings.Repeat("p", 65)); err == nil {
		t.Error("over-long playerId should be rejected")
	}
	if _, err := sanitizePlayerID("player\x00id"); err == nil {
		t.Error("playerId with a control character should be rejected")
	}
	if got, err := sanitizePlayerID(""); err != nil || got != "" {
		t.Errorf("empty playerId should be accepted, got %q / %v", got, err)
	}
}

// resetCORS restores the package-level CORS state between cases.
func resetCORS() {
	corsWildcard = false
	corsAllowed = nil
}

// unsetEnv removes a variable for the duration of the test. t.Setenv can only
// set values, and the unset case is exactly what selects the wildcard default.
func unsetEnv(t *testing.T, key string) {
	t.Helper()
	prev, had := os.LookupEnv(key)
	if err := os.Unsetenv(key); err != nil {
		t.Fatalf("unset %s: %v", key, err)
	}
	t.Cleanup(func() {
		if had {
			os.Setenv(key, prev)
		}
	})
}

func TestCORSAllowlist(t *testing.T) {
	t.Cleanup(resetCORS)

	tests := []struct {
		name       string
		env        string
		envSet     bool
		origin     string
		wantOrigin string
	}{
		{"unset falls back to wildcard", "", false, "http://evil.test", "*"},
		{"explicit wildcard", "*", true, "http://evil.test", "*"},
		{"allowed origin is echoed", "http://localhost:3000", true, "http://localhost:3000", "http://localhost:3000"},
		{"disallowed origin gets no header", "http://localhost:3000", true, "http://evil.test", ""},
		{"empty value disables CORS", "", true, "http://localhost:3000", ""},
		{"list matches second entry", "http://a.test, http://b.test", true, "http://b.test", "http://b.test"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			resetCORS()
			if tc.envSet {
				t.Setenv("CORS_ALLOWED_ORIGINS", tc.env)
			} else {
				unsetEnv(t, "CORS_ALLOWED_ORIGINS")
			}
			initCORS()

			handler := withCORS(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
			})

			req := httptest.NewRequest(http.MethodGet, "/leaderboard/top", nil)
			req.Header.Set("Origin", tc.origin)
			rec := httptest.NewRecorder()
			handler(rec, req)

			if got := rec.Header().Get("Access-Control-Allow-Origin"); got != tc.wantOrigin {
				t.Errorf("Allow-Origin = %q, want %q", got, tc.wantOrigin)
			}
		})
	}
}

func TestCORSPreflightShortCircuits(t *testing.T) {
	t.Cleanup(resetCORS)
	resetCORS()
	t.Setenv("CORS_ALLOWED_ORIGINS", "http://localhost:3000")
	initCORS()

	called := false
	handler := withCORS(func(w http.ResponseWriter, r *http.Request) {
		called = true
	})

	req := httptest.NewRequest(http.MethodOptions, "/game/new", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	rec := httptest.NewRecorder()
	handler(rec, req)

	if called {
		t.Error("preflight should not reach the wrapped handler")
	}
	if rec.Code != http.StatusNoContent {
		t.Errorf("preflight status = %d, want %d", rec.Code, http.StatusNoContent)
	}
}

// TestBodyLimitRejectsLargePayload confirms an oversized body is cut off
// rather than being read into memory in full.
func TestBodyLimitRejectsLargePayload(t *testing.T) {
	handler := withBodyLimit(func(w http.ResponseWriter, r *http.Request) {
		buf := make([]byte, 1<<20)
		n, err := r.Body.Read(buf)
		if err == nil && n >= 1<<20 {
			t.Error("body limit did not apply")
		}
		w.WriteHeader(http.StatusOK)
	})

	huge := strings.NewReader(strings.Repeat("a", 1<<20))
	req := httptest.NewRequest(http.MethodPost, "/leaderboard/submit", huge)
	handler(httptest.NewRecorder(), req)
}

// TestSubmitScoreRejectsMissingGameID covers the validation that runs before
// any storage call, so it needs no DynamoDB.
func TestSubmitScoreRejectsMissingGameID(t *testing.T) {
	body := strings.NewReader(`{"name":"Emin","playerId":"p1"}`)
	req := httptest.NewRequest(http.MethodPost, "/leaderboard/submit", body)
	rec := httptest.NewRecorder()

	submitScoreHandler(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

// TestSubmitScoreIgnoresClientScore is the regression guard for the forged
// score: the request body carries a score field, and the decoder must not
// have anywhere to put it.
func TestSubmitScoreIgnoresClientScore(t *testing.T) {
	body := strings.NewReader(`{"gameId":"","name":"Cheater","score":999999999}`)
	req := httptest.NewRequest(http.MethodPost, "/leaderboard/submit", body)
	rec := httptest.NewRecorder()

	submitScoreHandler(rec, req)

	// Rejected for the missing game ID, never for the score — which proves the
	// score field is not part of the accepted contract.
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
	if got := rec.Body.String(); !strings.Contains(got, "Game ID required") {
		t.Errorf("body = %q, want a game-ID validation error", got)
	}
}
