package main

import (
	"log"
	"net/http"
	"os"
	"strings"
)

// maxRequestBodyBytes caps request bodies. Every endpoint here accepts a small
// JSON object, so anything larger is either a bug or an attempt to make the
// server allocate on demand.
const maxRequestBodyBytes = 4 << 10 // 4 KiB

// CORS behaviour is driven by CORS_ALLOWED_ORIGINS:
//
//	unset            -> "*" (permissive; preserves the previous behaviour)
//	set to "*"       -> "*"
//	set but empty    -> no CORS headers at all, for same-origin deployments
//	comma-separated  -> explicit allowlist, echoed back per request
var (
	corsWildcard bool
	corsAllowed  []string
)

func initCORS() {
	raw, ok := os.LookupEnv("CORS_ALLOWED_ORIGINS")
	if !ok {
		corsWildcard = true
		log.Println("CORS: CORS_ALLOWED_ORIGINS unset, allowing all origins (*)")
		return
	}

	for _, origin := range strings.Split(raw, ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" {
			continue
		}
		if origin == "*" {
			corsWildcard = true
			corsAllowed = nil
			log.Println("CORS: allowing all origins (*)")
			return
		}
		corsAllowed = append(corsAllowed, origin)
	}

	if len(corsAllowed) == 0 {
		log.Println("CORS: no origins allowed (same-origin only)")
		return
	}
	log.Printf("CORS: allowed origins: %s", strings.Join(corsAllowed, ", "))
}

func originAllowed(origin string) bool {
	for _, allowed := range corsAllowed {
		if allowed == origin {
			return true
		}
	}
	return false
}

func withCORS(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")

		switch {
		case corsWildcard:
			w.Header().Set("Access-Control-Allow-Origin", "*")
		case origin != "" && originAllowed(origin):
			// Echo the specific origin, and vary on it so shared caches do not
			// serve one origin's response to another.
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Add("Vary", "Origin")
		}

		if w.Header().Get("Access-Control-Allow-Origin") != "" {
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		h(w, r)
	}
}

// withBodyLimit bounds how much of a request body the server will read.
func withBodyLimit(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)
		}
		h(w, r)
	}
}

// withMiddleware applies the standard wrappers to a handler.
func withMiddleware(h http.HandlerFunc) http.HandlerFunc {
	return withCORS(withBodyLimit(h))
}
