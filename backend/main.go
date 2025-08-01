package main

import (
	"context"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	rand.Seed(time.Now().UnixNano())

	// Initialize storage backends
	initStorage()

	// Initialize leaderboard
	initLeaderboard()

	// Game cleanup is now handled by DynamoDB TTL

	// Game endpoints
	http.HandleFunc("/health", withCORS(healthHandler))
	http.HandleFunc("/game/new", withCORS(newGameHandler))
	http.HandleFunc("/game/move", withCORS(moveHandler))
	http.HandleFunc("/game/state", withCORS(stateHandler))

	// Leaderboard endpoints
	http.HandleFunc("/leaderboard/submit", withCORS(submitScoreHandler))
	http.HandleFunc("/leaderboard/top", withCORS(leaderboardHandler))
	http.HandleFunc("/leaderboard/rank", withCORS(playerRankHandler))
	http.HandleFunc("/leaderboard/stats", withCORS(statsHandler))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	server := &http.Server{
		Addr:    ":" + port,
		Handler: nil,
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

	// Cleanup storage connections
	cleanupStorage()

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}
