package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	// Resolve the CORS policy before any request can be served
	initCORS()

	// Initialize storage backends
	initStorage()

	// Initialize leaderboard
	initLeaderboard()

	// Game cleanup is now handled by DynamoDB TTL

	// Game endpoints
	http.HandleFunc("/health", withMiddleware(healthHandler))
	http.HandleFunc("/game/new", withMiddleware(newGameHandler))
	http.HandleFunc("/game/move", withMiddleware(moveHandler))
	http.HandleFunc("/game/state", withMiddleware(stateHandler))

	// Leaderboard endpoints
	http.HandleFunc("/leaderboard/submit", withMiddleware(submitScoreHandler))
	http.HandleFunc("/leaderboard/top", withMiddleware(leaderboardHandler))
	http.HandleFunc("/leaderboard/rank", withMiddleware(playerRankHandler))
	http.HandleFunc("/leaderboard/stats", withMiddleware(statsHandler))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	// Timeouts are set explicitly: http.Server's zero value applies none at all,
	// so a client that opens a connection and dribbles out a request header can
	// hold a goroutine indefinitely (Slowloris). ReadHeaderTimeout is the one
	// that closes that specific hole.
	//
	// WriteTimeout is deliberately generous. It covers the whole handler, and
	// the slowest path — POST /leaderboard/submit — chains four AWS calls:
	// loadGameSession (10s) + claimSubmission (10s) + saveEntryToDynamoDB (10s)
	// + the synchronous S3 backup (30s) = 60s worst case. The leaderboard read
	// path can also reach 60s (a 30s DynamoDB load, then a 30s S3 fallback).
	// Anything at or below 60s here would cut off slow-but-valid requests, so
	// this bounds a stuck connection without inventing a new failure mode.
	// Tighten it only alongside those constants in storage.go.
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           nil,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       20 * time.Second, // bodies are capped at 4 KiB
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		log.Printf("Server started on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// Drain in-flight requests BEFORE tearing down storage: those requests are
	// still reading and writing DynamoDB, so releasing their dependencies first
	// would fail them at the finish line. cleanupStorage is a no-op today, which
	// is the only reason the previous order was harmless.
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	// Cleanup storage connections
	cleanupStorage()

	log.Println("Server exited")
}
