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
